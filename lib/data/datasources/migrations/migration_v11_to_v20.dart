import 'package:sqflite_sqlcipher/sqflite.dart';
import 'migration_helpers.dart';

class MigrationV11ToV20 {
  /// v11: Create shifts table
  static Future<void> migrateV11(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS shifts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shift_number TEXT NOT NULL,
          cashier_id INTEGER,
          cash_box_id INTEGER NOT NULL,
          opening_amount REAL NOT NULL DEFAULT 0.0,
          closing_amount REAL,
          expected_amount REAL,
          difference REAL,
          status TEXT NOT NULL DEFAULT 'open',
          opened_at TEXT NOT NULL,
          closed_at TEXT,
          notes TEXT,
          total_sales REAL NOT NULL DEFAULT 0.0,
          total_returns REAL NOT NULL DEFAULT 0.0,
          total_discounts REAL NOT NULL DEFAULT 0.0,
          transaction_count INTEGER NOT NULL DEFAULT 0,
          currency TEXT NOT NULL DEFAULT 'YER',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (cashier_id) REFERENCES users (id),
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_cashier_id ON shifts (cashier_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_cash_box_id ON shifts (cash_box_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts (status)');
  }

  /// v12: Add shift columns to invoices, create currency_exchanges and cash_transfers
  static Future<void> migrateV12(Database db) async {
    // Add shift-related columns to invoices
    try {
      await db.execute('ALTER TABLE invoices ADD COLUMN shift_id INTEGER');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute('ALTER TABLE invoices ADD COLUMN cashier_name TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN is_posted INTEGER NOT NULL DEFAULT 0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Create indexes for new invoice columns
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_shift_id ON invoices (shift_id)');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoices_is_posted ON invoices (is_posted)');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Create currency_exchanges table (صرافة العملات)
    await db.execute('''
        CREATE TABLE IF NOT EXISTS currency_exchanges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exchange_number TEXT NOT NULL,
          from_currency TEXT NOT NULL,
          to_currency TEXT NOT NULL,
          from_amount REAL NOT NULL,
          to_amount REAL NOT NULL,
          exchange_rate REAL NOT NULL,
          from_cash_box_id INTEGER NOT NULL,
          to_cash_box_id INTEGER NOT NULL,
          gain_loss REAL NOT NULL DEFAULT 0.0,
          gain_loss_type TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (from_cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (to_cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');

    // Create cash_transfers table (تحويل بين الصناديق)
    await db.execute('''
        CREATE TABLE IF NOT EXISTS cash_transfers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transfer_number TEXT NOT NULL,
          from_cash_box_id INTEGER NOT NULL,
          to_cash_box_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          currency TEXT NOT NULL DEFAULT 'YER',
          notes TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (from_cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (to_cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');

    // Create indexes for new tables
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_currency_exchanges_number ON currency_exchanges (exchange_number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_currency_exchanges_created_at ON currency_exchanges (created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_transfers_number ON cash_transfers (transfer_number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_transfers_created_at ON cash_transfers (created_at)');

    // Update currency exchange rates: SAR = 140 YER, USD = 530 YER
    try {
      await db.update('currencies', {'exchange_rate': 140.0},
          where: 'code = ?', whereArgs: ['SAR']);
      await db.update('currencies', {'exchange_rate': 530.0},
          where: 'code = ?', whereArgs: ['USD']);
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v13: Add currency to cash_boxes, cashier_name to shifts
  static Future<void> migrateV13(Database db) async {
    // Add currency column to cash_boxes
    try {
      await db.execute(
          "ALTER TABLE cash_boxes ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add cashier_name column to shifts
    try {
      await db.execute("ALTER TABLE shifts ADD COLUMN cashier_name TEXT");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v14: Add image_path to products
  static Future<void> migrateV14(Database db) async {
    // Add image_path column to products
    try {
      await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v15: Re-apply v13 columns (fixes missing columns from fresh installs)
  static Future<void> migrateV15(Database db) async {
    try {
      await db.execute(
          "ALTER TABLE cash_boxes ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute('ALTER TABLE shifts ADD COLUMN cashier_name TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v16: Re-create expense and transport accounts deleted by v9
  static Future<void> migrateV16(Database db) async {
    final now16 = DateTime.now().toIso8601String();
    final accountsToRestore = [
      {
        'name_ar': 'حساب المصاريف (ر.ي)',
        'name_en': 'Expenses Account (YER)',
        'account_code': '5000',
        'account_type': 'EXPENSE',
        'currency': 'YER',
        'symbol': 'ر.ي'
      },
      {
        'name_ar': 'حساب المصاريف (ر.س)',
        'name_en': 'Expenses Account (SAR)',
        'account_code': '5001',
        'account_type': 'EXPENSE',
        'currency': 'SAR',
        'symbol': 'ر.س'
      },
      {
        'name_ar': r'حساب المصاريف ($)',
        'name_en': 'Expenses Account (USD)',
        'account_code': '5002',
        'account_type': 'EXPENSE',
        'currency': 'USD',
        'symbol': r'\$'
      },
      {
        'name_ar': 'اجور نقل (ر.ي)',
        'name_en': 'Transport Charges (YER)',
        'account_code': '5200',
        'account_type': 'EXPENSE',
        'currency': 'YER',
        'symbol': 'ر.ي'
      },
      {
        'name_ar': 'اجور نقل (ر.س)',
        'name_en': 'Transport Charges (SAR)',
        'account_code': '5201',
        'account_type': 'EXPENSE',
        'currency': 'SAR',
        'symbol': 'ر.س'
      },
      {
        'name_ar': r'اجور نقل ($)',
        'name_en': 'Transport Charges (USD)',
        'account_code': '5202',
        'account_type': 'EXPENSE',
        'currency': 'USD',
        'symbol': r'\$'
      },
    ];
    for (final acct in accountsToRestore) {
      // Only insert if the account does not already exist
      final existing = await db.query('accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [acct['account_code'], acct['currency']],
          limit: 1);
      if (existing.isEmpty) {
        await db.insert('accounts', {
          'name_ar': acct['name_ar'],
          'name_en': acct['name_en'],
          'account_code': acct['account_code'],
          'account_type': acct['account_type'],
          'balance': 0,
          'currency': acct['currency'],
          'is_active': 1,
          'is_system': 1,
          'debt_ceiling': 0,
          'balance_type': 'credit',
          'created_at': now16,
          'updated_at': now16,
        });
      }
    }
  }

  /// v17: Create audit_log table
  static Future<void> migrateV17(Database db) async {
    // Add audit_log table for tracking data changes
    await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          table_name TEXT NOT NULL,
          record_id INTEGER,
          details TEXT,
          timestamp TEXT NOT NULL
        )
      ''');
  }

  /// v18: Create vouchers and voucher_items tables
  static Future<void> migrateV18(Database db) async {
    // Vouchers (السندات) - v18
    await db.execute('''
        CREATE TABLE IF NOT EXISTS vouchers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_number TEXT NOT NULL,
          voucher_type TEXT NOT NULL,
          date TEXT NOT NULL,
          description TEXT,
          currency TEXT NOT NULL DEFAULT 'YER',
          total_amount REAL NOT NULL DEFAULT 0.0,
          cash_box_id INTEGER,
          is_posted INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id)
        )
      ''');

    // Voucher line items (بنود السند) - v18
    await db.execute('''
        CREATE TABLE IF NOT EXISTS voucher_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_id INTEGER NOT NULL,
          account_id INTEGER NOT NULL,
          debit REAL NOT NULL DEFAULT 0.0,
          credit REAL NOT NULL DEFAULT 0.0,
          description TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (voucher_id) REFERENCES vouchers (id) ON DELETE CASCADE,
          FOREIGN KEY (account_id) REFERENCES accounts (id)
        )
      ''');

    // Voucher indexes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_voucher_number ON vouchers (voucher_number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_voucher_type ON vouchers (voucher_type)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_date ON vouchers (date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_created_at ON vouchers (created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_voucher_items_voucher_id ON voucher_items (voucher_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_voucher_items_account_id ON voucher_items (account_id)');
  }

  /// v19: Create stock_transfers, stocktaking_sessions, stocktaking_items
  static Future<void> migrateV19(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_transfers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transfer_number TEXT NOT NULL,
          from_warehouse_id INTEGER NOT NULL,
          to_warehouse_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          quantity REAL NOT NULL,
          notes TEXT,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (from_warehouse_id) REFERENCES warehouses (id),
          FOREIGN KEY (to_warehouse_id) REFERENCES warehouses (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');

    await db.execute('''
        CREATE TABLE IF NOT EXISTS stocktaking_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_number TEXT NOT NULL,
          warehouse_id INTEGER,
          date TEXT NOT NULL,
          total_items INTEGER NOT NULL DEFAULT 0,
          matched_items INTEGER NOT NULL DEFAULT 0,
          mismatched_items INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'draft',
          notes TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
        )
      ''');

    await db.execute('''
        CREATE TABLE IF NOT EXISTS stocktaking_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          system_quantity REAL NOT NULL,
          actual_quantity REAL NOT NULL,
          difference REAL NOT NULL,
          FOREIGN KEY (session_id) REFERENCES stocktaking_sessions (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_transfers_number ON stock_transfers (transfer_number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_transfers_from_wh ON stock_transfers (from_warehouse_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_transfers_to_wh ON stock_transfers (to_warehouse_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_transfers_product ON stock_transfers (product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_transfers_date ON stock_transfers (date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stocktaking_sessions_number ON stocktaking_sessions (session_number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stocktaking_sessions_wh ON stocktaking_sessions (warehouse_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stocktaking_items_session ON stocktaking_items (session_id)');
  }

  /// v20: Fix supplier balance_type, add debt_ceiling, seed new accounts
  static Future<void> migrateV20(Database db) async {
    // Add debt_ceiling column to suppliers
    try {
      await db.execute(
          'ALTER TABLE suppliers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add contact_method column to suppliers
    try {
      await db.execute(
          "ALTER TABLE suppliers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Fix supplier balance_type default to 'credit' (we typically owe the supplier)
    try {
      await db.execute(
          "UPDATE suppliers SET balance_type = 'credit' WHERE balance_type = 'debit' AND balance >= 0");
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add customer_id and supplier_id columns to vouchers
    try {
      await db.execute('ALTER TABLE vouchers ADD COLUMN customer_id INTEGER');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute('ALTER TABLE vouchers ADD COLUMN supplier_id INTEGER');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Seed new accounts for each currency if they don't exist
    final now20 = DateTime.now().toIso8601String();
    final newAccountTemplates = [
      // Inventory account (ASSET, code 1300+offset)
      {
        'baseCode': 1300,
        'nameAr': 'المخزون',
        'nameEn': 'Inventory Account',
        'type': 'ASSET'
      },
      // Opening Balance Equity (EQUITY, code 2901+offset) — P-04: was LIABILITY, now EQUITY; v43: code moved from 2200 to 2901
      {
        'baseCode': 2901,
        'nameAr': 'رصيد افتتاحي',
        'nameEn': 'Opening Balance Equity',
        'type': 'EQUITY'
      },
      // Retained Earnings (EQUITY, code 2900+offset) — P-04: was LIABILITY, now EQUITY
      {
        'baseCode': 2900,
        'nameAr': 'الأرباح المحتجزة',
        'nameEn': 'Retained Earnings',
        'type': 'EQUITY'
      },
      // COGS account (COST, code 3200+offset)
      {
        'baseCode': 3200,
        'nameAr': 'تكلفة البضاعة المباعة',
        'nameEn': 'COGS Account',
        'type': 'COST'
      },
    ];
    final currencyConfigs20 = [
      {'code': 'YER', 'symbol': 'ر.ي', 'offset': 0},
      {'code': 'SAR', 'symbol': 'ر.س', 'offset': 1},
      {'code': 'USD', 'symbol': r'$', 'offset': 2},
    ];
    for (final currency in currencyConfigs20) {
      final currencyCode = currency['code'] as String;
      final currencySymbol = currency['symbol'] as String;
      final codeOffset = currency['offset'] as int;
      for (final template in newAccountTemplates) {
        final actualCode =
            ((template['baseCode'] as int) + codeOffset).toString();
        final existing = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [actualCode, currencyCode],
            limit: 1);
        if (existing.isEmpty) {
          await db.insert('accounts', {
            'name_ar': '${template['nameAr']} ($currencySymbol)',
            'name_en': '${template['nameEn']} ($currencyCode)',
            'account_code': actualCode,
            'account_type': template['type'],
            'balance': 0,
            'currency': currencyCode,
            'is_active': 1,
            'is_system': 1,
            'debt_ceiling': 0,
            'balance_type': 'credit',
            'created_at': now20,
            'updated_at': now20,
          });
        }
      }
    }
  }
}
