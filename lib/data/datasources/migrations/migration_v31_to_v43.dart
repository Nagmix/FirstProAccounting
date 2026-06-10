import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/utils/money_helper.dart';
import 'seeds.dart';
import 'migration_helpers.dart';

class MigrationV31ToV43 {
  /// v31: Add original_invoice_id to invoices
  static Future<void> migrateV31(Database db) async {
    try {
      await db
          .execute('ALTER TABLE invoices ADD COLUMN original_invoice_id TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_original ON invoices (original_invoice_id)');
  }

  /// v32: Ensure stock_movements and unit_conversions exist, add cost_price
  static Future<void> migrateV32(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          movement_type TEXT NOT NULL,
          quantity REAL NOT NULL,
          reference_type TEXT,
          reference_id TEXT,
          notes TEXT,
          unit_cost REAL NOT NULL DEFAULT 0.0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_type ON stock_movements (movement_type)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_ref ON stock_movements (reference_type, reference_id)');

    await db.execute('''
        CREATE TABLE IF NOT EXISTS unit_conversions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          from_unit TEXT NOT NULL,
          to_unit TEXT NOT NULL,
          from_unit_id INTEGER,
          to_unit_id INTEGER,
          conversion_factor REAL NOT NULL,
          barcode TEXT,
          sell_price REAL NOT NULL DEFAULT 0.0,
          cost_price REAL NOT NULL DEFAULT 0.0,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_unit_conversions_product ON unit_conversions (product_id)');

    // Add cost_price column to unit_conversions if it doesn't exist
    try {
      await db.execute(
          'ALTER TABLE unit_conversions ADD COLUMN cost_price REAL NOT NULL DEFAULT 0.0');
    } catch (e) {
      MigrationHelpers.logMigrationError("alter", e);
      // Column already exists, ignore
    }
  }

  /// v33: Add held_orders table for POS held orders
  static Future<void> migrateV33(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS held_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_id INTEGER,
          cart_data TEXT NOT NULL,
          payment_method TEXT NOT NULL DEFAULT 'cash',
          payments_data TEXT NOT NULL DEFAULT '[]',
          discount REAL NOT NULL DEFAULT 0.0,
          discount_type TEXT NOT NULL DEFAULT 'none',
          customer_id INTEGER,
          customer_name TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE CASCADE
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_held_orders_shift ON held_orders (shift_id)');
  }

  /// v34: Convert REAL monetary columns to INTEGER (cents)
  static Future<void> migrateV34(Database db) async {
    await migrateV34RealToInteger(db);
    // M-05: Add unique constraint on (account_code, currency)
    try {
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_code_currency ON accounts (account_code, currency)');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v35: Fix EXPENSE balance_type, add EQUITY type, move accounts
  static Future<void> migrateV35(Database db) async {
    // Fix EXPENSE accounts that have incorrect 'credit' balance_type
    await db.execute(
      "UPDATE accounts SET balance_type = 'debit' WHERE account_type = 'EXPENSE' AND balance_type != 'debit'",
    );

    // Recalculate balances for EXPENSE accounts from journal entries
    final expenseAccounts = await db.query(
      'accounts',
      columns: ['id'],
      where: "account_type = 'EXPENSE'",
    );
    for (final row in expenseAccounts) {
      final accountId = row['id'] as int;
      final txResult = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit FROM transactions WHERE account_id = ?',
        [accountId],
      );
      final totalDebit =
          MoneyHelper.readCalculatedMoney(txResult.first['total_debit']);
      final totalCredit =
          MoneyHelper.readCalculatedMoney(txResult.first['total_credit']);
      // EXPENSE is debit-nature: balance = debit - credit
      final correctBalance = totalDebit - totalCredit;
      await db.update(
        'accounts',
        {
          'balance': MoneyHelper.toCents(correctBalance),
          'updated_at': DateTime.now().toIso8601String()
        },
        where: 'id = ?',
        whereArgs: [accountId],
      );
    }

    // Move Opening Balance Equity (code 2200/2201/2202) and
    // Retained Earnings (code 2900/2901/2902) from LIABILITY to EQUITY
    await db.execute(
      "UPDATE accounts SET account_type = 'EQUITY' WHERE account_code IN ('2200','2201','2202','2900','2901','2902') AND account_type = 'LIABILITY'",
    );

    // Fix any existing EQUITY accounts that may have wrong balance_type
    // EQUITY is credit-nature (like LIABILITY)
    await db.execute(
      "UPDATE accounts SET balance_type = 'credit' WHERE account_type = 'EQUITY' AND balance_type != 'credit'",
    );

    // Recalculate balances for migrated EQUITY accounts
    final equityAccounts = await db.query(
      'accounts',
      columns: ['id'],
      where: "account_type = 'EQUITY'",
    );
    for (final row in equityAccounts) {
      final accountId = row['id'] as int;
      final txResult = await db.rawQuery(
        'SELECT CAST(COALESCE(SUM(debit), 0) AS INTEGER) AS total_debit, CAST(COALESCE(SUM(credit), 0) AS INTEGER) AS total_credit FROM transactions WHERE account_id = ?',
        [accountId],
      );
      final totalDebit =
          MoneyHelper.readCalculatedMoney(txResult.first['total_debit']);
      final totalCredit =
          MoneyHelper.readCalculatedMoney(txResult.first['total_credit']);
      // EQUITY is credit-nature: balance = credit - debit
      final correctBalance = totalCredit - totalDebit;
      await db.update(
        'accounts',
        {
          'balance': MoneyHelper.toCents(correctBalance),
          'updated_at': DateTime.now().toIso8601String()
        },
        where: 'id = ?',
        whereArgs: [accountId],
      );
    }
  }

  /// v36: Add unit_cost column to invoice_items
  static Future<void> migrateV36(Database db) async {
    // Add unit_cost column for accurate COGS on deferred POS posting
    try {
      await db.execute(
          'ALTER TABLE invoice_items ADD COLUMN unit_cost INTEGER NOT NULL DEFAULT 0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration v36 unit_cost", e);
    }
  }

  /// v37: Add currency column to products
  static Future<void> migrateV37(Database db) async {
    try {
      await db.execute(
          "ALTER TABLE products ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v38: FIFO/LIFO costing, Bank Reconciliation
  static Future<void> migrateV38(Database db) async {
    // 1A: Add costing_method to products
    try {
      await db.execute(
          "ALTER TABLE products ADD COLUMN costing_method TEXT NOT NULL DEFAULT 'weighted_average'");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration v38 costing_method", e);
    }

    // 1B: Create inventory_cost_layers table
    try {
      await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_cost_layers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            warehouse_id INTEGER,
            quantity_original REAL NOT NULL,
            quantity_remaining REAL NOT NULL,
            unit_cost INTEGER NOT NULL DEFAULT 0,
            acquisition_date TEXT NOT NULL,
            reference_type TEXT,
            reference_id TEXT,
            is_fully_consumed INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
          )
        ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cost_layers_product ON inventory_cost_layers (product_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cost_layers_fifo ON inventory_cost_layers (product_id, acquisition_date, quantity_remaining) WHERE is_fully_consumed = 0');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cost_layers_consumed ON inventory_cost_layers (is_fully_consumed)');
    } catch (e) {
      MigrationHelpers.logMigrationError(
          "migration v38 inventory_cost_layers", e);
    }

    // 1C: Create movement_cost_allocations table
    try {
      await db.execute('''
          CREATE TABLE IF NOT EXISTS movement_cost_allocations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            cost_layer_id INTEGER NOT NULL,
            invoice_id TEXT,
            quantity_used REAL NOT NULL,
            unit_cost INTEGER NOT NULL DEFAULT 0,
            total_cost INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
            FOREIGN KEY (cost_layer_id) REFERENCES inventory_cost_layers (id)
          )
        ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_mca_product ON movement_cost_allocations (product_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_mca_layer ON movement_cost_allocations (cost_layer_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_mca_invoice ON movement_cost_allocations (invoice_id)');
    } catch (e) {
      MigrationHelpers.logMigrationError(
          "migration v38 movement_cost_allocations", e);
    }

    // 2A: Create bank_reconciliations table
    try {
      await db.execute('''
          CREATE TABLE IF NOT EXISTS bank_reconciliations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reconciliation_number TEXT NOT NULL,
            cash_box_id INTEGER NOT NULL,
            statement_date TEXT NOT NULL,
            statement_balance INTEGER NOT NULL DEFAULT 0,
            book_balance INTEGER NOT NULL DEFAULT 0,
            deposits_in_transit INTEGER NOT NULL DEFAULT 0,
            outstanding_checks INTEGER NOT NULL DEFAULT 0,
            bank_charges INTEGER NOT NULL DEFAULT 0,
            interest_earned INTEGER NOT NULL DEFAULT 0,
            nsf_checks INTEGER NOT NULL DEFAULT 0,
            other_adjustments INTEGER NOT NULL DEFAULT 0,
            adjusted_bank_balance INTEGER NOT NULL DEFAULT 0,
            adjusted_book_balance INTEGER NOT NULL DEFAULT 0,
            difference INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'draft',
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id)
          )
        ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_recon_cash_box ON bank_reconciliations (cash_box_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_recon_status ON bank_reconciliations (status)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_recon_number ON bank_reconciliations (reconciliation_number)');
    } catch (e) {
      MigrationHelpers.logMigrationError(
          "migration v38 bank_reconciliations", e);
    }

    // 2A: Create bank_statement_lines table
    try {
      await db.execute('''
          CREATE TABLE IF NOT EXISTS bank_statement_lines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reconciliation_id INTEGER,
            cash_box_id INTEGER NOT NULL,
            transaction_date TEXT NOT NULL,
            transaction_type TEXT NOT NULL DEFAULT 'debit',
            amount INTEGER NOT NULL DEFAULT 0,
            reference TEXT,
            description TEXT,
            match_status TEXT NOT NULL DEFAULT 'unmatched',
            matched_transaction_id INTEGER,
            is_book_entry INTEGER NOT NULL DEFAULT 0,
            source_type TEXT,
            source_id TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_stmt_recon ON bank_statement_lines (reconciliation_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_stmt_cash_box ON bank_statement_lines (cash_box_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_stmt_status ON bank_statement_lines (match_status)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bank_stmt_date ON bank_statement_lines (transaction_date)');
    } catch (e) {
      MigrationHelpers.logMigrationError(
          "migration v38 bank_statement_lines", e);
    }

    // Initialize cost layers for existing products
    // CostingEngineService requires DatabaseHelper instance - skip during migration
    // This will be initialized on first app launch instead
  }

  /// v39: Fix balance_type for all accounts
  static Future<void> migrateV39(Database db) async {
    await db.transaction((txn) async {
      // Fix balance_type for ASSET accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('ASSET') AND balance_type != 'debit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_asset_balance_type", e);
      }

      // Fix balance_type for EXPENSE accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('EXPENSE') AND balance_type != 'debit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_expense_balance_type", e);
      }

      // Fix balance_type for LIABILITY accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('LIABILITY') AND balance_type != 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_liability_balance_type", e);
      }

      // Fix balance_type for REVENUE accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('REVENUE') AND balance_type != 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_revenue_balance_type", e);
      }

      // Fix balance_type for EQUITY accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('EQUITY') AND balance_type != 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_equity_balance_type", e);
      }

      // Fix old exchange account (5300) that was EXPENSE/credit → now should be EXPENSE/debit
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_code = '5300' AND account_type = 'EXPENSE' AND balance_type = 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_exchange_account", e);
      }
    });
  }

  /// v40: Add UNIQUE constraint on invoice numbers, add balance_type to transactions
  static Future<void> migrateV40(Database db) async {
    try {
      // C-05: Add UNIQUE index on invoice id to prevent duplicates
      // Since id is already PRIMARY KEY, we add a UNIQUE index on a composite to catch duplicates
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_unique_id ON invoices(id)');

      // C-07: Add balance_type column to transactions table
      // Records the account's balance_type at the time of the transaction,
      // preventing historical data corruption if account balance_type changes later
      await db.execute('ALTER TABLE transactions ADD COLUMN balance_type TEXT');

      // Backfill balance_type from accounts table
      await db.execute('''
          UPDATE transactions SET balance_type = (
            SELECT a.balance_type FROM accounts a WHERE a.id = transactions.account_id
          )
        ''');

      // B-01: Create Bank Charges Expense account (5250) for each currency
      // This separates bank charges from transport charges (5200)
      final currencies = ['YER', 'SAR', 'USD'];
      // ignore: unused_local_variable
      final currencySymbols = {'YER': 'ر.ي', 'SAR': 'ر.س', 'USD': r'$'};
      for (int i = 0; i < currencies.length; i++) {
        final currency = currencies[i];
        final codeOffset = i;
        final bankChargesCode = (5250 + codeOffset).toString();
        // Check if account already exists
        final existing = await db.rawQuery(
          'SELECT id FROM accounts WHERE account_code = ? AND currency = ?',
          [bankChargesCode, currency],
        );
        if (existing.isEmpty) {
          await db.insert('accounts', {
            'name_ar': 'رسوم بنكية ($currency)',
            'name_en': 'Bank Charges Expense ($currency)',
            'account_code': bankChargesCode,
            'account_type': 'EXPENSE',
            'balance': 0,
            'currency': currency,
            'balance_type': 'debit',
            'is_active': 1,
            'is_system': 1,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v40', e);
    }
  }

  /// v41: Accounting tree hierarchy, rename VAT 3300→2300
  static Future<void> migrateV41(Database db) async {
    final now = DateTime.now().toIso8601String();
    final currencies = ['YER', 'SAR', 'USD'];
    final offsets = [0, 1, 2];

    for (int i = 0; i < currencies.length; i++) {
      final currency = currencies[i];
      final offset = offsets[i];

      // ── 1. Rename VAT from 3300+offset → 2300+offset (move to LIABILITY range) ──
      final oldVatCode = (3300 + offset).toString();
      final newVatCode = (2300 + offset).toString();
      final vatRows = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [oldVatCode, currency]);
      if (vatRows.isNotEmpty) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [newVatCode, currency]);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': newVatCode, 'updated_at': now},
              where: 'id = ?', whereArgs: [vatRows.first['id']]);
        }
      }

      // ── 2. Rename Retained Earnings from 2900+offset → 2910+offset ──
      final oldRetainedCode = (2900 + offset).toString();
      final newRetainedCode = (2910 + offset).toString();
      final retainedRows = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [oldRetainedCode, currency]);
      if (retainedRows.isNotEmpty) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [newRetainedCode, currency]);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': newRetainedCode, 'updated_at': now},
              where: 'id = ?', whereArgs: [retainedRows.first['id']]);
        }
      }

      // ── 3. Add missing group/parent accounts if they don't exist ──
      final groupAccounts = [
        {
          'code': (2000 + offset).toString(),
          'name_ar': 'حساب الخصوم',
          'name_en': 'Liabilities Account',
          'type': 'LIABILITY'
        },
        {
          'code': (2900 + offset).toString(),
          'name_ar': 'حقوق الملكية',
          'name_en': 'Equity Account',
          'type': 'EQUITY'
        },
        {
          'code': (3000 + offset).toString(),
          'name_ar': 'حساب التكاليف',
          'name_en': 'Cost Account',
          'type': 'COST'
        },
        {
          'code': (4000 + offset).toString(),
          'name_ar': 'حساب الإيرادات',
          'name_en': 'Revenue Account',
          'type': 'REVENUE'
        },
      ];
      for (final group in groupAccounts) {
        final exists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [group['code'], currency]);
        if (exists.isEmpty) {
          await db.insert('accounts', {
            'name_ar':
                '${group['name_ar']} (${currency == 'YER' ? 'ر.ي' : currency == 'SAR' ? 'ر.س' : r'$'})',
            'name_en': '${group['name_en']} ($currency)',
            'account_code': group['code'],
            'account_type': group['type'],
            'balance': 0,
            'currency': currency,
            'balance_type': (group['type'] == 'ASSET' ||
                    group['type'] == 'COST' ||
                    group['type'] == 'EXPENSE')
                ? 'debit'
                : 'credit',
            'parent_id': null,
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }
      }

      // ── 4. Set parent_id for child accounts ──
      final parentMappings = {
        (1100 + offset).toString():
            (1000 + offset).toString(), // Cash&Banks → Assets
        (1200 + offset).toString():
            (1000 + offset).toString(), // Customers → Assets
        (1300 + offset).toString():
            (1000 + offset).toString(), // Inventory → Assets
        (2100 + offset).toString():
            (2000 + offset).toString(), // Suppliers → Liabilities
        (2300 + offset).toString():
            (2000 + offset).toString(), // VAT → Liabilities (new code)
        (2901 + offset).toString():
            (2900 + offset).toString(), // Opening Balance → Equity
        (2910 + offset).toString():
            (2900 + offset).toString(), // Retained Earnings → Equity (new code)
        (3100 + offset).toString():
            (3000 + offset).toString(), // Purchases → Costs
        (3200 + offset).toString(): (3000 + offset).toString(), // COGS → Costs
        (4100 + offset).toString():
            (4000 + offset).toString(), // Sales → Revenue
        (4400 + offset).toString():
            (4000 + offset).toString(), // Variance Income → Revenue
        (5100 + offset).toString():
            (5000 + offset).toString(), // Employees → Expenses
        (5200 + offset).toString():
            (5000 + offset).toString(), // Transport → Expenses
        (5250 + offset).toString():
            (5000 + offset).toString(), // Bank Charges → Expenses
        (5500 + offset).toString():
            (5000 + offset).toString(), // Variance Loss → Expenses
      };

      for (final entry in parentMappings.entries) {
        final childCode = entry.key;
        final parentCode = entry.value;
        final childRows = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [childCode, currency]);
        final parentRows = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [parentCode, currency]);
        if (childRows.isNotEmpty && parentRows.isNotEmpty) {
          final parentId = parentRows.first['id'];
          await db.update(
              'accounts', {'parent_id': parentId, 'updated_at': now},
              where: 'id = ?', whereArgs: [childRows.first['id']]);
        }
      }
    }
  }

  /// v42: Fix account codes and hierarchy
  static Future<void> migrateV42(Database db) async {
    final now = DateTime.now().toIso8601String();

    // 1. Rename exchange gains account code 5310 → 4700
    try {
      final oldGainRows = await db
          .query('accounts', where: 'account_code = ?', whereArgs: ['5310']);
      for (final row in oldGainRows) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ?', whereArgs: ['4700'], limit: 1);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': '4700', 'updated_at': now},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_exchange_gains', e);
    }

    // 2. Rename discount allowed account code 4500 → 5400
    try {
      final oldDiscountRows = await db
          .query('accounts', where: 'account_code = ?', whereArgs: ['4500']);
      for (final row in oldDiscountRows) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ?', whereArgs: ['5400'], limit: 1);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': '5400', 'updated_at': now},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_discount_code', e);
    }

    // 3. Set parent_id for orphaned dynamic accounts (5250, 5300, 5400 → parent 5000)
    try {
      final expenseRoot = await db.query('accounts',
          where: 'account_code = ? AND account_type = ?',
          whereArgs: ['5000', 'EXPENSE'],
          limit: 1);
      if (expenseRoot.isNotEmpty) {
        final expenseParentId = expenseRoot.first['id'];
        final orphanCodes = ['5250', '5300', '5400'];
        for (final code in orphanCodes) {
          await db.update(
              'accounts', {'parent_id': expenseParentId, 'updated_at': now},
              where:
                  'account_code = ? AND parent_id IS NULL AND account_type = ?',
              whereArgs: [code, 'EXPENSE']);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_expense_parent', e);
    }

    // 4. Set parent_id for revenue dynamic accounts (4600, 4700 → parent 4000)
    try {
      final revenueRoot = await db.query('accounts',
          where: 'account_code = ? AND account_type = ?',
          whereArgs: ['4000', 'REVENUE'],
          limit: 1);
      if (revenueRoot.isNotEmpty) {
        final revenueParentId = revenueRoot.first['id'];
        final orphanCodes = ['4600', '4700'];
        for (final code in orphanCodes) {
          await db.update(
              'accounts', {'parent_id': revenueParentId, 'updated_at': now},
              where:
                  'account_code = ? AND parent_id IS NULL AND account_type = ?',
              whereArgs: [code, 'REVENUE']);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_revenue_parent', e);
    }

    // 5. Seed missing accounts from updated templates (4600, 4700, 5250, 5300, 5400)
    try {
      await DatabaseSeeds.seedDefaultAccounts(db);
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_seed_accounts', e);
    }
  }

  /// v43: Rename Opening Balance Equity code 2200→2901
  static Future<void> migrateV43(Database db) async {
    final now = DateTime.now().toIso8601String();
    final codeOffsets = [0, 1, 2]; // YER, SAR, USD

    // ── Step 1: Rename Opening Balance Equity 2200 → 2901 ──
    for (final offset in codeOffsets) {
      final oldCode = (2200 + offset).toString();
      final newCode = (2901 + offset).toString();

      try {
        final oldRows = await db
            .query('accounts', where: 'account_code = ?', whereArgs: [oldCode]);
        for (final row in oldRows) {
          final currency = row['currency'] as String? ?? 'YER';
          final newCodeExists = await db.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [newCode, currency],
              limit: 1);

          if (newCodeExists.isEmpty) {
            await db.update(
                'accounts', {'account_code': newCode, 'updated_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          } else {
            final oldAccountId = row['id'] as int;
            final newAccountId = newCodeExists.first['id'] as int;
            await db.update('transactions', {'account_id': newAccountId},
                where: 'account_id = ?', whereArgs: [oldAccountId]);
            await db
                .delete('accounts', where: 'id = ?', whereArgs: [oldAccountId]);
          }
        }
      } catch (e) {
        MigrationHelpers.logMigrationError('v43_rename_2200_$offset', e);
      }
    }

    // ── Step 2: Rename Inventory Variance Loss 5400 → 5500 ──
    for (final offset in codeOffsets) {
      final oldCode = (5400 + offset).toString();
      final newCode = (5500 + offset).toString();

      try {
        final oldRows = await db.query('accounts',
            where:
                "account_code = ? AND (name_ar LIKE '%تفاوت%' OR name_en LIKE '%Variance%')",
            whereArgs: [oldCode]);
        for (final row in oldRows) {
          final currency = row['currency'] as String? ?? 'YER';
          final newCodeExists = await db.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [newCode, currency],
              limit: 1);

          if (newCodeExists.isEmpty) {
            await db.update(
                'accounts', {'account_code': newCode, 'updated_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          } else {
            final oldAccountId = row['id'] as int;
            final newAccountId = newCodeExists.first['id'] as int;
            await db.update('transactions', {'account_id': newAccountId},
                where: 'account_id = ?', whereArgs: [oldAccountId]);
            await db
                .delete('accounts', where: 'id = ?', whereArgs: [oldAccountId]);
          }
        }
      } catch (e) {
        MigrationHelpers.logMigrationError(
            'v43_rename_variance_5400_$offset', e);
      }
    }

    // ── Step 3: Seed new/missing accounts from updated templates ──
    try {
      await DatabaseSeeds.seedDefaultAccounts(db);
    } catch (e) {
      MigrationHelpers.logMigrationError('v43_seed_accounts', e);
    }
  }

  /// C-06: Migrate all REAL monetary columns to INTEGER (cents).
  static Future<void> migrateV34RealToInteger(Database db) async {
    // Helper: money columns use CAST(ROUND(col*100) AS INTEGER)
    // Non-money REAL columns (quantities, rates) copy as-is.
    // ignore: unused_local_variable
    const m = 'CAST(ROUND(col*100) AS INTEGER)'; // just a comment reminder

    await db.transaction((txn) async {
      // ── accounts ──
      await txn.execute('''
        CREATE TABLE temp_accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name_ar TEXT NOT NULL,
          name_en TEXT NOT NULL DEFAULT '',
          parent_id INTEGER,
          account_code TEXT NOT NULL,
          account_type TEXT NOT NULL DEFAULT 'ASSET',
          balance INTEGER NOT NULL DEFAULT 0,
          currency TEXT NOT NULL DEFAULT 'YER',
          linked_cash_box_id INTEGER,
          is_active INTEGER NOT NULL DEFAULT 1,
          is_system INTEGER NOT NULL DEFAULT 0,
          debt_ceiling INTEGER NOT NULL DEFAULT 0,
          balance_type TEXT NOT NULL DEFAULT 'debit',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (parent_id) REFERENCES accounts (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_accounts (id, name_ar, name_en, parent_id, account_code, account_type,
          balance, currency, linked_cash_box_id, is_active, is_system, debt_ceiling, balance_type, created_at, updated_at)
        SELECT id, name_ar, name_en, parent_id, account_code, account_type,
          CAST(ROUND(balance*100) AS INTEGER), currency, linked_cash_box_id, is_active, is_system,
          CAST(ROUND(debt_ceiling*100) AS INTEGER), balance_type, created_at, updated_at
        FROM accounts
      ''');
      await txn.execute('DROP TABLE accounts');
      await txn.execute('ALTER TABLE temp_accounts RENAME TO accounts');
      await txn.execute(
          'CREATE INDEX idx_accounts_account_code ON accounts (account_code)');
      await txn.execute(
          'CREATE INDEX idx_accounts_account_type ON accounts (account_type)');

      // ── products ──
      await txn.execute('''
        CREATE TABLE temp_products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_code TEXT,
          name_ar TEXT NOT NULL,
          name_en TEXT NOT NULL DEFAULT '',
          barcode TEXT,
          category_id INTEGER,
          unit_id INTEGER,
          supplier_id INTEGER,
          group_id TEXT,
          description TEXT,
          cost_price INTEGER NOT NULL DEFAULT 0,
          average_cost INTEGER NOT NULL DEFAULT 0,
          sell_price INTEGER NOT NULL DEFAULT 0,
          wholesale_price INTEGER NOT NULL DEFAULT 0,
          special_wholesale_price INTEGER NOT NULL DEFAULT 0,
          minimum_sale_price INTEGER NOT NULL DEFAULT 0,
          tax_rate REAL NOT NULL DEFAULT 0.0,
          tax_inclusive INTEGER NOT NULL DEFAULT 0,
          sales_account_id INTEGER,
          purchase_account_id INTEGER,
          inventory_account_id INTEGER,
          cogs_account_id INTEGER,
          vat_account_id INTEGER,
          current_stock REAL NOT NULL DEFAULT 0.0,
          min_stock REAL NOT NULL DEFAULT 0.0,
          warehouse_id INTEGER,
          expiry_date TEXT,
          expiry_tracking INTEGER NOT NULL DEFAULT 0,
          weight REAL NOT NULL DEFAULT 0.0,
          notes TEXT,
          include_in_reports INTEGER NOT NULL DEFAULT 1,
          is_active INTEGER NOT NULL DEFAULT 1,
          image_path TEXT,
          has_variants INTEGER NOT NULL DEFAULT 0,
          base_unit_id INTEGER,
          purchase_unit_id INTEGER,
          sale_unit_id INTEGER,
          track_stock INTEGER NOT NULL DEFAULT 1,
          is_sellable INTEGER NOT NULL DEFAULT 1,
          is_purchasable INTEGER NOT NULL DEFAULT 1,
          allow_negative INTEGER NOT NULL DEFAULT 0,
          sell_retail INTEGER NOT NULL DEFAULT 1,
          show_in_pos INTEGER NOT NULL DEFAULT 1,
          supplier_code TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (category_id) REFERENCES categories (id),
          FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
          FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_products SELECT
          id, item_code, name_ar, name_en, barcode, category_id, unit_id, supplier_id, group_id, description,
          CAST(ROUND(cost_price*100) AS INTEGER),
          CAST(ROUND(average_cost*100) AS INTEGER),
          CAST(ROUND(sell_price*100) AS INTEGER),
          CAST(ROUND(wholesale_price*100) AS INTEGER),
          CAST(ROUND(special_wholesale_price*100) AS INTEGER),
          CAST(ROUND(minimum_sale_price*100) AS INTEGER),
          tax_rate, tax_inclusive, sales_account_id, purchase_account_id, inventory_account_id, cogs_account_id, vat_account_id,
          current_stock, min_stock, warehouse_id, expiry_date, expiry_tracking, weight, notes,
          include_in_reports, is_active, image_path, has_variants, base_unit_id, purchase_unit_id, sale_unit_id,
          track_stock, is_sellable, is_purchasable, allow_negative, sell_retail, show_in_pos, supplier_code,
          created_at, updated_at
        FROM products
      ''');
      await txn.execute('DROP TABLE products');
      await txn.execute('ALTER TABLE temp_products RENAME TO products');
      await txn
          .execute('CREATE INDEX idx_products_barcode ON products (barcode)');
      await txn.execute(
          'CREATE INDEX idx_products_item_code ON products (item_code)');
      await txn.execute(
          'CREATE INDEX idx_products_category_id ON products (category_id)');

      // ── customers ──
      await txn.execute('''
        CREATE TABLE temp_customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          address TEXT,
          address2 TEXT,
          email TEXT,
          contact_method TEXT DEFAULT 'whatsapp',
          notes TEXT,
          balance INTEGER NOT NULL DEFAULT 0,
          balance_type TEXT NOT NULL DEFAULT 'credit',
          currency TEXT NOT NULL DEFAULT 'YER',
          debt_ceiling INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_customers SELECT
          id, name, phone, address, address2, email, contact_method, notes,
          CAST(ROUND(balance*100) AS INTEGER), balance_type, currency,
          CAST(ROUND(debt_ceiling*100) AS INTEGER), created_at, updated_at
        FROM customers
      ''');
      await txn.execute('DROP TABLE customers');
      await txn.execute('ALTER TABLE temp_customers RENAME TO customers');

      // ── invoices ──
      await txn.execute('''
        CREATE TABLE temp_invoices (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          payment_mechanism TEXT NOT NULL DEFAULT 'cash',
          payment_method TEXT NOT NULL DEFAULT 'cash',
          is_return INTEGER NOT NULL DEFAULT 0,
          cash_box_id INTEGER,
          customer_id INTEGER,
          supplier_id INTEGER,
          subtotal INTEGER NOT NULL DEFAULT 0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount INTEGER NOT NULL DEFAULT 0,
          tax_amount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL DEFAULT 0,
          paid_amount INTEGER NOT NULL DEFAULT 0,
          remaining INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'pending',
          cashier_id INTEGER,
          warehouse_id INTEGER,
          notes TEXT,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          transport_charges INTEGER NOT NULL DEFAULT 0,
          ewallet_provider TEXT,
          bank_transfer_provider TEXT,
          transfer_number TEXT,
          attachment_path TEXT,
          shift_id INTEGER,
          cashier_name TEXT,
          is_posted INTEGER NOT NULL DEFAULT 0,
          original_invoice_id TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers (id),
          FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (original_invoice_id) REFERENCES invoices (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_invoices SELECT
          id, type, payment_mechanism, payment_method, is_return, cash_box_id, customer_id, supplier_id,
          CAST(ROUND(subtotal*100) AS INTEGER), discount_rate,
          CAST(ROUND(discount_amount*100) AS INTEGER),
          CAST(ROUND(tax_amount*100) AS INTEGER),
          CAST(ROUND(total*100) AS INTEGER),
          CAST(ROUND(paid_amount*100) AS INTEGER),
          CAST(ROUND(remaining*100) AS INTEGER),
          status, cashier_id, warehouse_id, notes, currency, exchange_rate,
          CAST(ROUND(transport_charges*100) AS INTEGER),
          ewallet_provider, bank_transfer_provider, transfer_number, attachment_path,
          shift_id, cashier_name, is_posted, original_invoice_id, created_at
        FROM invoices
      ''');
      await txn.execute('DROP TABLE invoices');
      await txn.execute('ALTER TABLE temp_invoices RENAME TO invoices');
      await txn.execute(
          'CREATE INDEX idx_invoices_customer_id ON invoices (customer_id)');
      await txn.execute(
          'CREATE INDEX idx_invoices_created_at ON invoices (created_at)');
      await txn
          .execute('CREATE INDEX idx_invoices_status ON invoices (status)');
      await txn
          .execute('CREATE INDEX idx_invoices_shift_id ON invoices (shift_id)');
      await txn.execute(
          'CREATE INDEX idx_invoices_is_posted ON invoices (is_posted)');
      await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_original ON invoices (original_invoice_id)');

      // ── invoice_items ──
      await txn.execute('''
        CREATE TABLE temp_invoice_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id TEXT NOT NULL,
          product_id INTEGER NOT NULL,
          product_name TEXT NOT NULL,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price INTEGER NOT NULL DEFAULT 0,
          total_price INTEGER NOT NULL DEFAULT 0,
          unit_name TEXT,
          conversion_factor REAL NOT NULL DEFAULT 1.0,
          base_quantity REAL NOT NULL DEFAULT 1.0,
          notes TEXT,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_invoice_items SELECT
          id, invoice_id, product_id, product_name, quantity,
          CAST(ROUND(unit_price*100) AS INTEGER),
          CAST(ROUND(total_price*100) AS INTEGER),
          unit_name, conversion_factor, base_quantity, notes
        FROM invoice_items
      ''');
      await txn.execute('DROP TABLE invoice_items');
      await txn
          .execute('ALTER TABLE temp_invoice_items RENAME TO invoice_items');
      await txn.execute(
          'CREATE INDEX idx_invoice_items_invoice_id ON invoice_items (invoice_id)');

      // ── transactions ──
      await txn.execute('''
        CREATE TABLE temp_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id INTEGER NOT NULL,
          journal_id INTEGER,
          debit INTEGER NOT NULL DEFAULT 0,
          credit INTEGER NOT NULL DEFAULT 0,
          description TEXT,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (account_id) REFERENCES accounts (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_transactions SELECT
          id, account_id, journal_id,
          CAST(ROUND(debit*100) AS INTEGER),
          CAST(ROUND(credit*100) AS INTEGER),
          description, date, created_at
        FROM transactions
      ''');
      await txn.execute('DROP TABLE transactions');
      await txn.execute('ALTER TABLE temp_transactions RENAME TO transactions');
      await txn.execute(
          'CREATE INDEX idx_transactions_account_id ON transactions (account_id)');
      await txn.execute(
          'CREATE INDEX idx_transactions_journal_id ON transactions (journal_id)');
      await txn
          .execute('CREATE INDEX idx_transactions_date ON transactions (date)');

      // ── cash_boxes ──
      await txn.execute('''
        CREATE TABLE temp_cash_boxes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'cash_box',
          bank_account_number TEXT,
          bank_name TEXT,
          bank_branch TEXT,
          currency TEXT NOT NULL DEFAULT 'YER',
          balance INTEGER NOT NULL DEFAULT 0,
          balance_type TEXT NOT NULL DEFAULT 'credit',
          linked_account_id INTEGER,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (linked_account_id) REFERENCES accounts (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_cash_boxes SELECT
          id, name, type, bank_account_number, bank_name, bank_branch, currency,
          CAST(ROUND(balance*100) AS INTEGER), balance_type, linked_account_id, is_active,
          created_at, updated_at
        FROM cash_boxes
      ''');
      await txn.execute('DROP TABLE cash_boxes');
      await txn.execute('ALTER TABLE temp_cash_boxes RENAME TO cash_boxes');
      await txn
          .execute('CREATE INDEX idx_cash_boxes_type ON cash_boxes (type)');

      // ── suppliers ──
      await txn.execute('''
        CREATE TABLE temp_suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          email TEXT,
          address TEXT,
          balance INTEGER NOT NULL DEFAULT 0,
          balance_type TEXT NOT NULL DEFAULT 'credit',
          currency TEXT NOT NULL DEFAULT 'YER',
          notes TEXT,
          debt_ceiling INTEGER NOT NULL DEFAULT 0,
          contact_method TEXT DEFAULT 'whatsapp',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_suppliers SELECT
          id, name, phone, email, address,
          CAST(ROUND(balance*100) AS INTEGER), balance_type, currency, notes,
          CAST(ROUND(debt_ceiling*100) AS INTEGER), contact_method, created_at, updated_at
        FROM suppliers
      ''');
      await txn.execute('DROP TABLE suppliers');
      await txn.execute('ALTER TABLE temp_suppliers RENAME TO suppliers');

      // ── expenses ──
      await txn.execute('''
        CREATE TABLE temp_expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          amount INTEGER NOT NULL DEFAULT 0,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          amount_base INTEGER NOT NULL DEFAULT 0,
          expense_date TEXT NOT NULL,
          category TEXT,
          payment_method TEXT NOT NULL DEFAULT 'cash',
          cash_box_id INTEGER,
          account_id INTEGER,
          beneficiary TEXT,
          reference_number TEXT,
          notes TEXT,
          is_recurring INTEGER NOT NULL DEFAULT 0,
          recurring_period TEXT,
          attachment_path TEXT,
          operation_type TEXT NOT NULL DEFAULT 'صرف',
          expense_account_id INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (account_id) REFERENCES accounts (id),
          FOREIGN KEY (expense_account_id) REFERENCES accounts (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_expenses SELECT
          id, title, description,
          CAST(ROUND(amount*100) AS INTEGER), currency, exchange_rate,
          CAST(ROUND(amount_base*100) AS INTEGER),
          expense_date, category, payment_method, cash_box_id, account_id,
          beneficiary, reference_number, notes, is_recurring, recurring_period,
          attachment_path, operation_type, expense_account_id, created_at, updated_at
        FROM expenses
      ''');
      await txn.execute('DROP TABLE expenses');
      await txn.execute('ALTER TABLE temp_expenses RENAME TO expenses');
      await txn
          .execute('CREATE INDEX idx_expenses_category ON expenses (category)');
      await txn.execute(
          'CREATE INDEX idx_expenses_expense_date ON expenses (expense_date)');
      await txn.execute(
          'CREATE INDEX idx_expenses_account_id ON expenses (account_id)');
      await txn.execute(
          'CREATE INDEX idx_expenses_expense_account_id ON expenses (expense_account_id)');

      // ── employees ──
      await txn.execute('''
        CREATE TABLE temp_employees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          job_title TEXT,
          balance INTEGER NOT NULL DEFAULT 0,
          balance_type TEXT NOT NULL DEFAULT 'credit',
          currency TEXT NOT NULL DEFAULT 'YER',
          account_id INTEGER,
          notes TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (account_id) REFERENCES accounts (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_employees SELECT
          id, name, phone, job_title,
          CAST(ROUND(balance*100) AS INTEGER), balance_type, currency, account_id, notes,
          is_active, created_at, updated_at
        FROM employees
      ''');
      await txn.execute('DROP TABLE employees');
      await txn.execute('ALTER TABLE temp_employees RENAME TO employees');
      await txn.execute('CREATE INDEX idx_employees_name ON employees (name)');
      await txn.execute(
          'CREATE INDEX idx_employees_is_active ON employees (is_active)');

      // ── quotations ──
      await txn.execute('''
        CREATE TABLE temp_quotations (
          id TEXT PRIMARY KEY,
          quotation_number TEXT NOT NULL,
          customer_id INTEGER,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          subtotal INTEGER NOT NULL DEFAULT 0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount INTEGER NOT NULL DEFAULT 0,
          tax_amount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'draft',
          valid_until TEXT,
          notes TEXT,
          terms_conditions TEXT,
          converted_to_sales_order INTEGER NOT NULL DEFAULT 0,
          sales_order_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_quotations SELECT
          id, quotation_number, customer_id, currency, exchange_rate,
          CAST(ROUND(subtotal*100) AS INTEGER), discount_rate,
          CAST(ROUND(discount_amount*100) AS INTEGER),
          CAST(ROUND(tax_amount*100) AS INTEGER),
          CAST(ROUND(total*100) AS INTEGER),
          status, valid_until, notes, terms_conditions,
          converted_to_sales_order, sales_order_id, created_at, updated_at
        FROM quotations
      ''');
      await txn.execute('DROP TABLE quotations');
      await txn.execute('ALTER TABLE temp_quotations RENAME TO quotations');
      await txn.execute(
          'CREATE INDEX idx_quotations_customer_id ON quotations (customer_id)');
      await txn
          .execute('CREATE INDEX idx_quotations_status ON quotations (status)');

      // ── quotation_items ──
      await txn.execute('''
        CREATE TABLE temp_quotation_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quotation_id TEXT NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          description TEXT,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price INTEGER NOT NULL DEFAULT 0,
          total_price INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (quotation_id) REFERENCES quotations (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_quotation_items SELECT
          id, quotation_id, product_id, product_name, description, quantity,
          CAST(ROUND(unit_price*100) AS INTEGER),
          CAST(ROUND(total_price*100) AS INTEGER)
        FROM quotation_items
      ''');
      await txn.execute('DROP TABLE quotation_items');
      await txn.execute(
          'ALTER TABLE temp_quotation_items RENAME TO quotation_items');
      await txn.execute(
          'CREATE INDEX idx_quotation_items_quotation_id ON quotation_items (quotation_id)');

      // ── purchase_orders ──
      await txn.execute('''
        CREATE TABLE temp_purchase_orders (
          id TEXT PRIMARY KEY,
          order_number TEXT NOT NULL,
          supplier_id INTEGER,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          subtotal INTEGER NOT NULL DEFAULT 0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount INTEGER NOT NULL DEFAULT 0,
          tax_amount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'draft',
          expected_date TEXT,
          notes TEXT,
          terms_conditions TEXT,
          warehouse_id INTEGER,
          converted_to_invoice INTEGER NOT NULL DEFAULT 0,
          invoice_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
          FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_purchase_orders SELECT
          id, order_number, supplier_id, currency, exchange_rate,
          CAST(ROUND(subtotal*100) AS INTEGER), discount_rate,
          CAST(ROUND(discount_amount*100) AS INTEGER),
          CAST(ROUND(tax_amount*100) AS INTEGER),
          CAST(ROUND(total*100) AS INTEGER),
          status, expected_date, notes, terms_conditions, warehouse_id,
          converted_to_invoice, invoice_id, created_at, updated_at
        FROM purchase_orders
      ''');
      await txn.execute('DROP TABLE purchase_orders');
      await txn.execute(
          'ALTER TABLE temp_purchase_orders RENAME TO purchase_orders');
      await txn.execute(
          'CREATE INDEX idx_purchase_orders_supplier_id ON purchase_orders (supplier_id)');
      await txn.execute(
          'CREATE INDEX idx_purchase_orders_status ON purchase_orders (status)');

      // ── purchase_order_items ──
      await txn.execute('''
        CREATE TABLE temp_purchase_order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_order_id TEXT NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          description TEXT,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price INTEGER NOT NULL DEFAULT 0,
          total_price INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_purchase_order_items SELECT
          id, purchase_order_id, product_id, product_name, description, quantity,
          CAST(ROUND(unit_price*100) AS INTEGER),
          CAST(ROUND(total_price*100) AS INTEGER)
        FROM purchase_order_items
      ''');
      await txn.execute('DROP TABLE purchase_order_items');
      await txn.execute(
          'ALTER TABLE temp_purchase_order_items RENAME TO purchase_order_items');
      await txn.execute(
          'CREATE INDEX idx_purchase_order_items_po_id ON purchase_order_items (purchase_order_id)');

      // ── sales_orders ──
      await txn.execute('''
        CREATE TABLE temp_sales_orders (
          id TEXT PRIMARY KEY,
          order_number TEXT NOT NULL,
          customer_id INTEGER,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          subtotal INTEGER NOT NULL DEFAULT 0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount INTEGER NOT NULL DEFAULT 0,
          tax_amount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'draft',
          expected_date TEXT,
          notes TEXT,
          terms_conditions TEXT,
          warehouse_id INTEGER,
          converted_to_invoice INTEGER NOT NULL DEFAULT 0,
          invoice_id TEXT,
          quotation_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers (id),
          FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_sales_orders SELECT
          id, order_number, customer_id, currency, exchange_rate,
          CAST(ROUND(subtotal*100) AS INTEGER), discount_rate,
          CAST(ROUND(discount_amount*100) AS INTEGER),
          CAST(ROUND(tax_amount*100) AS INTEGER),
          CAST(ROUND(total*100) AS INTEGER),
          status, expected_date, notes, terms_conditions, warehouse_id,
          converted_to_invoice, invoice_id, quotation_id, created_at, updated_at
        FROM sales_orders
      ''');
      await txn.execute('DROP TABLE sales_orders');
      await txn.execute('ALTER TABLE temp_sales_orders RENAME TO sales_orders');
      await txn.execute(
          'CREATE INDEX idx_sales_orders_customer_id ON sales_orders (customer_id)');
      await txn.execute(
          'CREATE INDEX idx_sales_orders_status ON sales_orders (status)');

      // ── sales_order_items ──
      await txn.execute('''
        CREATE TABLE temp_sales_order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sales_order_id TEXT NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          description TEXT,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price INTEGER NOT NULL DEFAULT 0,
          total_price INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (sales_order_id) REFERENCES sales_orders (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_sales_order_items SELECT
          id, sales_order_id, product_id, product_name, description, quantity,
          CAST(ROUND(unit_price*100) AS INTEGER),
          CAST(ROUND(total_price*100) AS INTEGER)
        FROM sales_order_items
      ''');
      await txn.execute('DROP TABLE sales_order_items');
      await txn.execute(
          'ALTER TABLE temp_sales_order_items RENAME TO sales_order_items');
      await txn.execute(
          'CREATE INDEX idx_sales_order_items_so_id ON sales_order_items (sales_order_id)');

      // ── shifts ──
      await txn.execute('''
        CREATE TABLE temp_shifts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_number TEXT NOT NULL,
          cashier_id INTEGER,
          cashier_name TEXT,
          cash_box_id INTEGER NOT NULL,
          opening_amount INTEGER NOT NULL DEFAULT 0,
          closing_amount INTEGER,
          expected_amount INTEGER,
          difference INTEGER,
          status TEXT NOT NULL DEFAULT 'open',
          opened_at TEXT NOT NULL,
          closed_at TEXT,
          notes TEXT,
          total_sales INTEGER NOT NULL DEFAULT 0,
          total_returns INTEGER NOT NULL DEFAULT 0,
          total_discounts INTEGER NOT NULL DEFAULT 0,
          transaction_count INTEGER NOT NULL DEFAULT 0,
          currency TEXT NOT NULL DEFAULT 'YER',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (cashier_id) REFERENCES users (id),
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_shifts SELECT
          id, shift_number, cashier_id, cashier_name, cash_box_id,
          CAST(ROUND(opening_amount*100) AS INTEGER),
          CAST(ROUND(COALESCE(closing_amount,0)*100) AS INTEGER),
          CAST(ROUND(COALESCE(expected_amount,0)*100) AS INTEGER),
          CAST(ROUND(COALESCE(difference,0)*100) AS INTEGER),
          status, opened_at, closed_at, notes,
          CAST(ROUND(total_sales*100) AS INTEGER),
          CAST(ROUND(total_returns*100) AS INTEGER),
          CAST(ROUND(total_discounts*100) AS INTEGER),
          transaction_count, currency, created_at, updated_at
        FROM shifts
      ''');
      await txn.execute('DROP TABLE shifts');
      await txn.execute('ALTER TABLE temp_shifts RENAME TO shifts');
      await txn
          .execute('CREATE INDEX idx_shifts_cashier_id ON shifts (cashier_id)');
      await txn.execute(
          'CREATE INDEX idx_shifts_cash_box_id ON shifts (cash_box_id)');
      await txn.execute('CREATE INDEX idx_shifts_status ON shifts (status)');

      // ── currency_exchanges ──
      await txn.execute('''
        CREATE TABLE temp_currency_exchanges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exchange_number TEXT NOT NULL,
          from_currency TEXT NOT NULL,
          to_currency TEXT NOT NULL,
          from_amount INTEGER NOT NULL,
          to_amount INTEGER NOT NULL,
          exchange_rate REAL NOT NULL,
          from_cash_box_id INTEGER NOT NULL,
          to_cash_box_id INTEGER NOT NULL,
          gain_loss INTEGER NOT NULL DEFAULT 0,
          gain_loss_type TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (from_cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (to_cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_currency_exchanges SELECT
          id, exchange_number, from_currency, to_currency,
          CAST(ROUND(from_amount*100) AS INTEGER),
          CAST(ROUND(to_amount*100) AS INTEGER),
          exchange_rate, from_cash_box_id, to_cash_box_id,
          CAST(ROUND(gain_loss*100) AS INTEGER),
          gain_loss_type, notes, created_at
        FROM currency_exchanges
      ''');
      await txn.execute('DROP TABLE currency_exchanges');
      await txn.execute(
          'ALTER TABLE temp_currency_exchanges RENAME TO currency_exchanges');
      await txn.execute(
          'CREATE INDEX idx_currency_exchanges_number ON currency_exchanges (exchange_number)');
      await txn.execute(
          'CREATE INDEX idx_currency_exchanges_created_at ON currency_exchanges (created_at)');

      // ── cash_transfers ──
      await txn.execute('''
        CREATE TABLE temp_cash_transfers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transfer_number TEXT NOT NULL,
          from_cash_box_id INTEGER NOT NULL,
          to_cash_box_id INTEGER NOT NULL,
          amount INTEGER NOT NULL,
          currency TEXT NOT NULL DEFAULT 'YER',
          notes TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (from_cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (to_cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_cash_transfers SELECT
          id, transfer_number, from_cash_box_id, to_cash_box_id,
          CAST(ROUND(amount*100) AS INTEGER), currency, notes, created_at
        FROM cash_transfers
      ''');
      await txn.execute('DROP TABLE cash_transfers');
      await txn
          .execute('ALTER TABLE temp_cash_transfers RENAME TO cash_transfers');
      await txn.execute(
          'CREATE INDEX idx_cash_transfers_number ON cash_transfers (transfer_number)');
      await txn.execute(
          'CREATE INDEX idx_cash_transfers_created_at ON cash_transfers (created_at)');

      // ── vouchers ──
      await txn.execute('''
        CREATE TABLE temp_vouchers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_number TEXT NOT NULL,
          voucher_type TEXT NOT NULL,
          date TEXT NOT NULL,
          description TEXT,
          currency TEXT NOT NULL DEFAULT 'YER',
          total_amount INTEGER NOT NULL DEFAULT 0,
          cash_box_id INTEGER,
          customer_id INTEGER,
          supplier_id INTEGER,
          is_posted INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (customer_id) REFERENCES customers (id),
          FOREIGN KEY (supplier_id) REFERENCES suppliers (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_vouchers SELECT
          id, voucher_number, voucher_type, date, description, currency,
          CAST(ROUND(total_amount*100) AS INTEGER),
          cash_box_id, customer_id, supplier_id, is_posted, created_at, updated_at
        FROM vouchers
      ''');
      await txn.execute('DROP TABLE vouchers');
      await txn.execute('ALTER TABLE temp_vouchers RENAME TO vouchers');
      await txn.execute(
          'CREATE INDEX idx_vouchers_voucher_number ON vouchers (voucher_number)');
      await txn.execute(
          'CREATE INDEX idx_vouchers_voucher_type ON vouchers (voucher_type)');
      await txn.execute('CREATE INDEX idx_vouchers_date ON vouchers (date)');
      await txn.execute(
          'CREATE INDEX idx_vouchers_created_at ON vouchers (created_at)');

      // ── voucher_items ──
      await txn.execute('''
        CREATE TABLE temp_voucher_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_id INTEGER NOT NULL,
          account_id INTEGER NOT NULL,
          debit INTEGER NOT NULL DEFAULT 0,
          credit INTEGER NOT NULL DEFAULT 0,
          description TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (voucher_id) REFERENCES vouchers (id) ON DELETE CASCADE,
          FOREIGN KEY (account_id) REFERENCES accounts (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_voucher_items SELECT
          id, voucher_id, account_id,
          CAST(ROUND(debit*100) AS INTEGER),
          CAST(ROUND(credit*100) AS INTEGER),
          description, created_at
        FROM voucher_items
      ''');
      await txn.execute('DROP TABLE voucher_items');
      await txn
          .execute('ALTER TABLE temp_voucher_items RENAME TO voucher_items');
      await txn.execute(
          'CREATE INDEX idx_voucher_items_voucher_id ON voucher_items (voucher_id)');
      await txn.execute(
          'CREATE INDEX idx_voucher_items_account_id ON voucher_items (account_id)');

      // ── inventory_vouchers ──
      await txn.execute('''
        CREATE TABLE temp_inventory_vouchers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_number TEXT NOT NULL,
          date TEXT NOT NULL,
          warehouse_id INTEGER,
          description TEXT,
          currency TEXT NOT NULL DEFAULT 'YER',
          total_value INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'approved',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_inventory_vouchers SELECT
          id, voucher_number, date, warehouse_id, description, currency,
          CAST(ROUND(total_value*100) AS INTEGER), status, created_at, updated_at
        FROM inventory_vouchers
      ''');
      await txn.execute('DROP TABLE inventory_vouchers');
      await txn.execute(
          'ALTER TABLE temp_inventory_vouchers RENAME TO inventory_vouchers');
      await txn.execute(
          'CREATE INDEX idx_inventory_vouchers_number ON inventory_vouchers (voucher_number)');
      await txn.execute(
          'CREATE INDEX idx_inventory_vouchers_date ON inventory_vouchers (date)');
      await txn.execute(
          'CREATE INDEX idx_inventory_vouchers_warehouse ON inventory_vouchers (warehouse_id)');
      await txn.execute(
          'CREATE INDEX idx_inventory_vouchers_status ON inventory_vouchers (status)');

      // ── inventory_voucher_items ──
      await txn.execute('''
        CREATE TABLE temp_inventory_voucher_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          system_quantity REAL NOT NULL,
          actual_quantity REAL NOT NULL,
          difference REAL NOT NULL,
          unit_cost INTEGER NOT NULL DEFAULT 0,
          total_value INTEGER NOT NULL DEFAULT 0,
          notes TEXT,
          FOREIGN KEY (voucher_id) REFERENCES inventory_vouchers (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_inventory_voucher_items SELECT
          id, voucher_id, product_id, system_quantity, actual_quantity, difference,
          CAST(ROUND(unit_cost*100) AS INTEGER),
          CAST(ROUND(total_value*100) AS INTEGER),
          notes
        FROM inventory_voucher_items
      ''');
      await txn.execute('DROP TABLE inventory_voucher_items');
      await txn.execute(
          'ALTER TABLE temp_inventory_voucher_items RENAME TO inventory_voucher_items');
      await txn.execute(
          'CREATE INDEX idx_inventory_voucher_items_voucher ON inventory_voucher_items (voucher_id)');
      await txn.execute(
          'CREATE INDEX idx_inventory_voucher_items_product ON inventory_voucher_items (product_id)');

      // ── fiscal_years ──
      await txn.execute('''
        CREATE TABLE temp_fiscal_years (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          year INTEGER NOT NULL UNIQUE,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'open',
          net_profit INTEGER NOT NULL DEFAULT 0,
          closed_at TEXT,
          closed_by TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_fiscal_years SELECT
          id, year, start_date, end_date, status,
          CAST(ROUND(net_profit*100) AS INTEGER),
          closed_at, closed_by, notes, created_at, updated_at
        FROM fiscal_years
      ''');
      await txn.execute('DROP TABLE fiscal_years');
      await txn.execute('ALTER TABLE temp_fiscal_years RENAME TO fiscal_years');
      await txn
          .execute('CREATE INDEX idx_fiscal_years_year ON fiscal_years (year)');
      await txn.execute(
          'CREATE INDEX idx_fiscal_years_status ON fiscal_years (status)');

      // ── unit_conversions ──
      await txn.execute('''
        CREATE TABLE temp_unit_conversions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          from_unit TEXT NOT NULL,
          to_unit TEXT NOT NULL,
          from_unit_id INTEGER,
          to_unit_id INTEGER,
          conversion_factor REAL NOT NULL,
          barcode TEXT,
          sell_price INTEGER NOT NULL DEFAULT 0,
          cost_price INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_unit_conversions SELECT
          id, product_id, from_unit, to_unit, from_unit_id, to_unit_id, conversion_factor, barcode,
          CAST(ROUND(sell_price*100) AS INTEGER),
          CAST(ROUND(cost_price*100) AS INTEGER),
          is_active, created_at, updated_at
        FROM unit_conversions
      ''');
      await txn.execute('DROP TABLE unit_conversions');
      await txn.execute(
          'ALTER TABLE temp_unit_conversions RENAME TO unit_conversions');
      await txn.execute(
          'CREATE INDEX idx_unit_conversions_product ON unit_conversions (product_id)');

      // ── stock_movements ──
      await txn.execute('''
        CREATE TABLE temp_stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          movement_type TEXT NOT NULL,
          quantity REAL NOT NULL,
          reference_type TEXT,
          reference_id TEXT,
          notes TEXT,
          unit_cost INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_stock_movements SELECT
          id, product_id, movement_type, quantity, reference_type, reference_id, notes,
          CAST(ROUND(unit_cost*100) AS INTEGER),
          created_at
        FROM stock_movements
      ''');
      await txn.execute('DROP TABLE stock_movements');
      await txn.execute(
          'ALTER TABLE temp_stock_movements RENAME TO stock_movements');
      await txn.execute(
          'CREATE INDEX idx_stock_movements_product ON stock_movements (product_id)');
      await txn.execute(
          'CREATE INDEX idx_stock_movements_type ON stock_movements (movement_type)');
      await txn.execute(
          'CREATE INDEX idx_stock_movements_ref ON stock_movements (reference_type, reference_id)');

      // ── held_orders ──
      await txn.execute('''
        CREATE TABLE temp_held_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_id INTEGER,
          cart_data TEXT NOT NULL,
          payment_method TEXT NOT NULL DEFAULT 'cash',
          payments_data TEXT NOT NULL DEFAULT '[]',
          discount INTEGER NOT NULL DEFAULT 0,
          discount_type TEXT NOT NULL DEFAULT 'none',
          customer_id INTEGER,
          customer_name TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('''
        INSERT INTO temp_held_orders SELECT
          id, shift_id, cart_data, payment_method, payments_data,
          CAST(ROUND(discount*100) AS INTEGER),
          discount_type, customer_id, customer_name, created_at
        FROM held_orders
      ''');
      await txn.execute('DROP TABLE held_orders');
      await txn.execute('ALTER TABLE temp_held_orders RENAME TO held_orders');
      await txn.execute(
          'CREATE INDEX idx_held_orders_shift ON held_orders (shift_id)');
    });
  }

  /// Migration v39 helper: Fix balance_type for all accounts
  static Future<void> migrateV39Helper(Database db) async {
    await db.transaction((txn) async {
      // Fix balance_type for ASSET accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('ASSET') AND balance_type != 'debit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_asset_balance_type", e);
      }

      // Fix balance_type for EXPENSE accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('EXPENSE') AND balance_type != 'debit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_expense_balance_type", e);
      }

      // Fix balance_type for LIABILITY accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('LIABILITY') AND balance_type != 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_liability_balance_type", e);
      }

      // Fix balance_type for REVENUE accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('REVENUE') AND balance_type != 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_revenue_balance_type", e);
      }

      // Fix balance_type for EQUITY accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('EQUITY') AND balance_type != 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_equity_balance_type", e);
      }

      // Fix old exchange account (5300) that was EXPENSE/credit → now should be EXPENSE/debit
      // The new separate accounts (5300=losses/debit, 4700=gains/credit) will be created automatically
      // when getOrCreateExchangeAccount is called next time.
      // Also fix old 5310 code → 4700 for exchange gains (REVENUE)
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_code = '5300' AND account_type = 'EXPENSE' AND balance_type = 'credit'",
        );
      } catch (e) {
        MigrationHelpers.logMigrationError(
            "migration v39 fix_exchange_account", e);
      }
    });
  }

  /// Migration v41 helper: Accounting tree hierarchy
  static Future<void> migrateV41Helper(Database db) async {
    final now = DateTime.now().toIso8601String();
    final currencies = ['YER', 'SAR', 'USD'];
    final offsets = [0, 1, 2];

    for (int i = 0; i < currencies.length; i++) {
      final currency = currencies[i];
      final offset = offsets[i];

      // ── 1. Rename VAT from 3300+offset → 2300+offset (move to LIABILITY range) ──
      final oldVatCode = (3300 + offset).toString();
      final newVatCode = (2300 + offset).toString();
      final vatRows = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [oldVatCode, currency]);
      if (vatRows.isNotEmpty) {
        // Check if new code already exists
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [newVatCode, currency]);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': newVatCode, 'updated_at': now},
              where: 'id = ?', whereArgs: [vatRows.first['id']]);
        }
      }

      // ── 2. Rename Retained Earnings from 2900+offset → 2910+offset ──
      // (2900 becomes the Equity parent group account)
      final oldRetainedCode = (2900 + offset).toString();
      final newRetainedCode = (2910 + offset).toString();
      final retainedRows = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [oldRetainedCode, currency]);
      if (retainedRows.isNotEmpty) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [newRetainedCode, currency]);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': newRetainedCode, 'updated_at': now},
              where: 'id = ?', whereArgs: [retainedRows.first['id']]);
        }
      }

      // ── 3. Add missing group/parent accounts if they don't exist ──
      final groupAccounts = [
        {
          'code': (2000 + offset).toString(),
          'name_ar': 'حساب الخصوم',
          'name_en': 'Liabilities Account',
          'type': 'LIABILITY'
        },
        {
          'code': (2900 + offset).toString(),
          'name_ar': 'حقوق الملكية',
          'name_en': 'Equity Account',
          'type': 'EQUITY'
        },
        {
          'code': (3000 + offset).toString(),
          'name_ar': 'حساب التكاليف',
          'name_en': 'Cost Account',
          'type': 'COST'
        },
        {
          'code': (4000 + offset).toString(),
          'name_ar': 'حساب الإيرادات',
          'name_en': 'Revenue Account',
          'type': 'REVENUE'
        },
      ];
      for (final group in groupAccounts) {
        final exists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [group['code'], currency]);
        if (exists.isEmpty) {
          await db.insert('accounts', {
            'name_ar':
                '${group['name_ar']} (${currency == 'YER' ? 'ر.ي' : currency == 'SAR' ? 'ر.س' : r'$'})',
            'name_en': '${group['name_en']} ($currency)',
            'account_code': group['code'],
            'account_type': group['type'],
            'balance': 0,
            'currency': currency,
            'balance_type': (group['type'] == 'ASSET' ||
                    group['type'] == 'COST' ||
                    group['type'] == 'EXPENSE')
                ? 'debit'
                : 'credit',
            'parent_id': null,
            'is_active': 1,
            'is_system': 1,
            'created_at': now,
            'updated_at': now,
          });
        }
      }

      // ── 4. Set parent_id for child accounts ──
      final parentMappings = {
        (1100 + offset).toString():
            (1000 + offset).toString(), // Cash&Banks → Assets
        (1200 + offset).toString():
            (1000 + offset).toString(), // Customers → Assets
        (1300 + offset).toString():
            (1000 + offset).toString(), // Inventory → Assets
        (2100 + offset).toString():
            (2000 + offset).toString(), // Suppliers → Liabilities
        (2300 + offset).toString():
            (2000 + offset).toString(), // VAT → Liabilities (new code)
        (2901 + offset).toString():
            (2900 + offset).toString(), // Opening Balance → Equity
        (2910 + offset).toString():
            (2900 + offset).toString(), // Retained Earnings → Equity (new code)
        (3100 + offset).toString():
            (3000 + offset).toString(), // Purchases → Costs
        (3200 + offset).toString(): (3000 + offset).toString(), // COGS → Costs
        (4100 + offset).toString():
            (4000 + offset).toString(), // Sales → Revenue
        (4400 + offset).toString():
            (4000 + offset).toString(), // Variance Income → Revenue
        (5100 + offset).toString():
            (5000 + offset).toString(), // Employees → Expenses
        (5200 + offset).toString():
            (5000 + offset).toString(), // Transport → Expenses
        (5250 + offset).toString():
            (5000 + offset).toString(), // Bank Charges → Expenses
        (5500 + offset).toString():
            (5000 + offset).toString(), // Variance Loss → Expenses
      };

      for (final entry in parentMappings.entries) {
        final childCode = entry.key;
        final parentCode = entry.value;
        final childRows = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [childCode, currency]);
        final parentRows = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [parentCode, currency]);
        if (childRows.isNotEmpty && parentRows.isNotEmpty) {
          final parentId = parentRows.first['id'];
          await db.update(
              'accounts', {'parent_id': parentId, 'updated_at': now},
              where: 'id = ?', whereArgs: [childRows.first['id']]);
        }
      }
    }
  }

  /// Migration v42 helper: Fix account codes and hierarchy
  static Future<void> migrateV42Helper(Database db) async {
    final now = DateTime.now().toIso8601String();

    // 1. Rename exchange gains account code 5310 → 4700
    try {
      final oldGainRows = await db
          .query('accounts', where: 'account_code = ?', whereArgs: ['5310']);
      for (final row in oldGainRows) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ?', whereArgs: ['4700'], limit: 1);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': '4700', 'updated_at': now},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_exchange_gains', e);
    }

    // 2. Rename discount allowed account code 4500 → 5400
    try {
      final oldDiscountRows = await db
          .query('accounts', where: 'account_code = ?', whereArgs: ['4500']);
      for (final row in oldDiscountRows) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ?', whereArgs: ['5400'], limit: 1);
        if (newCodeExists.isEmpty) {
          await db.update(
              'accounts', {'account_code': '5400', 'updated_at': now},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_discount_code', e);
    }

    // 3. Set parent_id for orphaned dynamic accounts (5250, 5300, 5400 → parent 5000)
    try {
      final expenseRoot = await db.query('accounts',
          where: 'account_code = ? AND account_type = ?',
          whereArgs: ['5000', 'EXPENSE'],
          limit: 1);
      if (expenseRoot.isNotEmpty) {
        final expenseParentId = expenseRoot.first['id'];
        final orphanCodes = ['5250', '5300', '5400'];
        for (final code in orphanCodes) {
          await db.update(
              'accounts', {'parent_id': expenseParentId, 'updated_at': now},
              where:
                  'account_code = ? AND parent_id IS NULL AND account_type = ?',
              whereArgs: [code, 'EXPENSE']);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_expense_parent', e);
    }

    // 4. Set parent_id for revenue dynamic accounts (4600, 4700 → parent 4000)
    try {
      final revenueRoot = await db.query('accounts',
          where: 'account_code = ? AND account_type = ?',
          whereArgs: ['4000', 'REVENUE'],
          limit: 1);
      if (revenueRoot.isNotEmpty) {
        final revenueParentId = revenueRoot.first['id'];
        final orphanCodes = ['4600', '4700'];
        for (final code in orphanCodes) {
          await db.update(
              'accounts', {'parent_id': revenueParentId, 'updated_at': now},
              where:
                  'account_code = ? AND parent_id IS NULL AND account_type = ?',
              whereArgs: [code, 'REVENUE']);
        }
      }
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_revenue_parent', e);
    }

    // 5. Seed missing accounts from updated templates (4600, 4700, 5250, 5300, 5400)
    try {
      await DatabaseSeeds.seedDefaultAccounts(db);
    } catch (e) {
      MigrationHelpers.logMigrationError('v42_seed_accounts', e);
    }
  }

  /// Migration v43 helper: Rename Opening Balance Equity
  static Future<void> migrateV43Helper(Database db) async {
    final now = DateTime.now().toIso8601String();
    final codeOffsets = [0, 1, 2]; // YER, SAR, USD

    // ── Step 1: Rename Opening Balance Equity 2200 → 2901 ──
    for (final offset in codeOffsets) {
      final oldCode = (2200 + offset).toString();
      final newCode = (2901 + offset).toString();

      try {
        final oldRows = await db
            .query('accounts', where: 'account_code = ?', whereArgs: [oldCode]);
        for (final row in oldRows) {
          final currency = row['currency'] as String? ?? 'YER';
          final newCodeExists = await db.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [newCode, currency],
              limit: 1);

          if (newCodeExists.isEmpty) {
            await db.update(
                'accounts', {'account_code': newCode, 'updated_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          } else {
            final oldAccountId = row['id'] as int;
            final newAccountId = newCodeExists.first['id'] as int;
            await db.update('transactions', {'account_id': newAccountId},
                where: 'account_id = ?', whereArgs: [oldAccountId]);
            await db
                .delete('accounts', where: 'id = ?', whereArgs: [oldAccountId]);
          }
        }
      } catch (e) {
        MigrationHelpers.logMigrationError('v43_rename_2200_$offset', e);
      }
    }

    // ── Step 2: Rename Inventory Variance Loss 5400 → 5500 ──
    // Only rename EXPENSE accounts at code 5400 that are "خسارة تفاوت الجرد"
    // (do NOT touch "خصم مسموح به" / Discount Allowed which is the correct 5400)
    for (final offset in codeOffsets) {
      final oldCode = (5400 + offset).toString();
      final newCode = (5500 + offset).toString();

      try {
        final oldRows = await db.query('accounts',
            where:
                "account_code = ? AND (name_ar LIKE '%تفاوت%' OR name_en LIKE '%Variance%')",
            whereArgs: [oldCode]);
        for (final row in oldRows) {
          final currency = row['currency'] as String? ?? 'YER';
          final newCodeExists = await db.query('accounts',
              where: 'account_code = ? AND currency = ?',
              whereArgs: [newCode, currency],
              limit: 1);

          if (newCodeExists.isEmpty) {
            await db.update(
                'accounts', {'account_code': newCode, 'updated_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          } else {
            final oldAccountId = row['id'] as int;
            final newAccountId = newCodeExists.first['id'] as int;
            await db.update('transactions', {'account_id': newAccountId},
                where: 'account_id = ?', whereArgs: [oldAccountId]);
            await db
                .delete('accounts', where: 'id = ?', whereArgs: [oldAccountId]);
          }
        }
      } catch (e) {
        MigrationHelpers.logMigrationError(
            'v43_rename_variance_5400_$offset', e);
      }
    }

    // ── Step 3: Seed new/missing accounts from updated templates ──
    try {
      await DatabaseSeeds.seedDefaultAccounts(db);
    } catch (e) {
      MigrationHelpers.logMigrationError('v43_seed_accounts', e);
    }
  }
}
