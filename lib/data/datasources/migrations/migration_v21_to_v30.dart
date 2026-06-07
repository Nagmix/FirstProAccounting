import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/utils/money_helper.dart';
import 'seeds.dart';
import 'migration_helpers.dart';

class MigrationV21ToV30 {
  /// v21: Add contact_method and debt_ceiling to customers
  static Future<void> migrateV21(Database db) async {
      // Add contact_method column to customers (replacing notification_method)
      try { await db.execute("ALTER TABLE customers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // Add debt_ceiling column to customers (replacing credit_limit)
      try { await db.execute('ALTER TABLE customers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // Copy data from old columns to new columns
      try { await db.execute("UPDATE customers SET contact_method = COALESCE(notification_method, 'whatsapp') WHERE contact_method IS NULL OR contact_method = 'whatsapp'"); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('UPDATE customers SET debt_ceiling = COALESCE(credit_limit, 0.0) WHERE debt_ceiling = 0.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
  }

  /// v22: Create inventory_vouchers, inventory_voucher_items, fiscal_years
  static Future<void> migrateV22(Database db) async {
      // Inventory Vouchers (سندات الجرد)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_vouchers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_number TEXT NOT NULL,
          date TEXT NOT NULL,
          warehouse_id INTEGER,
          description TEXT,
          currency TEXT NOT NULL DEFAULT 'YER',
          total_value REAL NOT NULL DEFAULT 0.0,
          status TEXT NOT NULL DEFAULT 'approved',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
        )
      ''');

      // Inventory Voucher Items (بنود سند الجرد)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_voucher_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          voucher_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          system_quantity REAL NOT NULL,
          actual_quantity REAL NOT NULL,
          difference REAL NOT NULL,
          unit_cost REAL NOT NULL DEFAULT 0.0,
          total_value REAL NOT NULL DEFAULT 0.0,
          notes TEXT,
          FOREIGN KEY (voucher_id) REFERENCES inventory_vouchers (id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');

      // Fiscal Years (السنوات المالية)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS fiscal_years (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          year INTEGER NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'open',
          net_profit REAL NOT NULL DEFAULT 0.0,
          closed_at TEXT,
          closed_by TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // v22 indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inventory_vouchers_number ON inventory_vouchers (voucher_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inventory_vouchers_date ON inventory_vouchers (date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inventory_vouchers_warehouse ON inventory_vouchers (warehouse_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inventory_vouchers_status ON inventory_vouchers (status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inventory_voucher_items_voucher ON inventory_voucher_items (voucher_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_inventory_voucher_items_product ON inventory_voucher_items (product_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_fiscal_years_year ON fiscal_years (year)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_fiscal_years_status ON fiscal_years (status)');
  }

  /// v23: Add UNIQUE constraint on fiscal_years.year (recreate table)
  static Future<void> migrateV23(Database db) async {
      // Recreate fiscal_years table with UNIQUE constraint on year
      // SQLite doesn't support adding UNIQUE via ALTER TABLE, so we:
      // 1. Create a temp table with the correct schema
      // 2. Copy data
      // 3. Drop old table
      // 4. Rename temp to original
      await db.execute('CREATE TABLE fiscal_years_v23 (id INTEGER PRIMARY KEY AUTOINCREMENT, year INTEGER NOT NULL UNIQUE, start_date TEXT NOT NULL, end_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'open\', net_profit REAL NOT NULL DEFAULT 0.0, closed_at TEXT, closed_by TEXT, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
      await db.execute('INSERT INTO fiscal_years_v23 SELECT id, year, start_date, end_date, status, net_profit, closed_at, closed_by, notes, created_at, updated_at FROM fiscal_years');
      await db.execute('DROP TABLE fiscal_years');
      await db.execute('ALTER TABLE fiscal_years_v23 RENAME TO fiscal_years');
      // Recreate indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_fiscal_years_year ON fiscal_years (year)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_fiscal_years_status ON fiscal_years (status)');
  }

  /// v24: Fix balance_type, Multi-Unit, Weighted Average Cost, Stock Movements
  static Future<void> migrateV24(Database db) async {
      // ── Fix balance_type: ASSET and COST accounts should be 'debit' ──
      await db.execute(
        "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('ASSET', 'COST') AND balance_type != 'debit'",
      );
      // Recalculate balances for affected accounts
      final affectedAccounts = await db.query(
        'accounts',
        columns: ['id'],
        where: "account_type IN ('ASSET', 'COST')",
      );
      for (final row in affectedAccounts) {
        final accountId = row['id'] as int;
        final txResult = await db.rawQuery(
          'SELECT CAST(COALESCE(SUM(debit) - SUM(credit), 0) AS INTEGER) AS net_debit FROM transactions WHERE account_id = ?',
          [accountId],
        );
        final correctBalance = MoneyHelper.readCalculatedMoney(txResult.first['net_debit']);
        await db.update(
          'accounts',
          {'balance': MoneyHelper.toCents(correctBalance), 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      }

      // ── Multi-Unit Conversion table ──
      // Supports selling/purchasing in different units (e.g., carton vs piece)
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
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_unit_conversions_product ON unit_conversions (product_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_unit_conversions_barcode ON unit_conversions (barcode)',
      );

      // ── Weighted Average Cost: add average_cost column ──
      try {
        await db.execute('ALTER TABLE products ADD COLUMN average_cost REAL NOT NULL DEFAULT 0.0');
      } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      // Initialize average_cost from existing cost_price
      await db.execute('UPDATE products SET average_cost = cost_price WHERE average_cost = 0.0 AND cost_price > 0.0');

      // ── Stock Movement Log ──
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
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_type ON stock_movements (movement_type)',
      );
  }

  /// v25: Units Master, Product Unit Fields, Invoice Item Unit Fields
  static Future<void> migrateV25(Database db) async {
      // ── Create units table ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS units (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name_ar TEXT NOT NULL,
          name_en TEXT NOT NULL DEFAULT '',
          abbreviation TEXT NOT NULL DEFAULT '',
          unit_type TEXT NOT NULL DEFAULT 'count',
          description TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          is_sellable INTEGER NOT NULL DEFAULT 1,
          is_purchasable INTEGER NOT NULL DEFAULT 1,
          is_packaging INTEGER NOT NULL DEFAULT 0,
          is_base_unit INTEGER NOT NULL DEFAULT 0,
          display_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_units_type ON units (unit_type)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_units_active ON units (is_active)');

      // ── Seed default units ──
      await DatabaseSeeds.seedDefaultUnits(db);

      // ── Add new product columns for unit management ──
      try { await db.execute('ALTER TABLE products ADD COLUMN base_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN purchase_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sale_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN tax_inclusive INTEGER NOT NULL DEFAULT 0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN allow_negative INTEGER NOT NULL DEFAULT 0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sell_retail INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN show_in_pos INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // Migrate existing unit_id → base_unit_id
      await db.execute('UPDATE products SET base_unit_id = unit_id WHERE base_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET sale_unit_id = unit_id WHERE sale_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET purchase_unit_id = unit_id WHERE purchase_unit_id IS NULL AND unit_id IS NOT NULL');

      // ── Add unit fields to invoice_items ──
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_name TEXT'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN base_quantity REAL NOT NULL DEFAULT 1.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // Backfill base_quantity from quantity for existing invoice items
      await db.execute('UPDATE invoice_items SET base_quantity = quantity WHERE base_quantity = 1.0 AND quantity != 1.0');

      // ── Update unit_conversions to use unit IDs ──
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN from_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN to_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
  }

  /// v26: Ensure ALL missing columns exist, add VAT account
  static Future<void> migrateV26(Database db) async {
      // ── Products table: add missing columns ──
      try { await db.execute('ALTER TABLE products ADD COLUMN average_cost REAL NOT NULL DEFAULT 0.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN tax_inclusive INTEGER NOT NULL DEFAULT 0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN expiry_tracking INTEGER NOT NULL DEFAULT 0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN has_variants INTEGER NOT NULL DEFAULT 0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN base_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN purchase_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sale_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN allow_negative INTEGER NOT NULL DEFAULT 0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sell_retail INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN show_in_pos INTEGER NOT NULL DEFAULT 1'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // Initialize average_cost from cost_price where average_cost is 0
      await db.execute('UPDATE products SET average_cost = cost_price WHERE average_cost = 0.0 AND cost_price > 0.0');

      // ── Create units table if not exists ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS units (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name_ar TEXT NOT NULL,
          name_en TEXT NOT NULL DEFAULT '',
          abbreviation TEXT NOT NULL DEFAULT '',
          unit_type TEXT NOT NULL DEFAULT 'count',
          description TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          is_sellable INTEGER NOT NULL DEFAULT 1,
          is_purchasable INTEGER NOT NULL DEFAULT 1,
          is_packaging INTEGER NOT NULL DEFAULT 0,
          is_base_unit INTEGER NOT NULL DEFAULT 0,
          display_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_units_type ON units (unit_type)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_units_active ON units (is_active)');

      // Seed default units
      await DatabaseSeeds.seedDefaultUnits(db);

      // ── Create unit_conversions table if not exists ──
      await db.execute('''
        CREATE TABLE IF NOT EXISTS unit_conversions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          from_unit TEXT NOT NULL,
          to_unit TEXT NOT NULL,
          conversion_factor REAL NOT NULL,
          barcode TEXT,
          sell_price REAL NOT NULL DEFAULT 0.0,
          is_active INTEGER NOT NULL DEFAULT 1,
          from_unit_id INTEGER,
          to_unit_id INTEGER,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unit_conversions_product ON unit_conversions (product_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unit_conversions_barcode ON unit_conversions (barcode)');

      // ── Add unit fields to invoice_items ──
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_name TEXT'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN base_quantity REAL NOT NULL DEFAULT 1.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // ── Add debt_ceiling and contact_method to customers ──
      try { await db.execute('ALTER TABLE customers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute("ALTER TABLE customers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // ── Add debt_ceiling and contact_method to suppliers ──
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute("ALTER TABLE suppliers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // ── Add operation_type and expense_account_id to expenses ──
      try { await db.execute("ALTER TABLE expenses ADD COLUMN operation_type TEXT NOT NULL DEFAULT 'صرف'"); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE expenses ADD COLUMN expense_account_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }

      // ── Migrate existing unit_id → base_unit_id ──
      await db.execute('UPDATE products SET base_unit_id = unit_id WHERE base_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET sale_unit_id = unit_id WHERE sale_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET purchase_unit_id = unit_id WHERE purchase_unit_id IS NULL AND unit_id IS NOT NULL');

      // ── Add VAT account (code 3300, LIABILITY) for each currency ──
      final now26 = DateTime.now().toIso8601String();
      final vatAccountTemplates = [
        {'code': 'YER', 'symbol': 'ر.ي', 'offset': 0},
        {'code': 'SAR', 'symbol': 'ر.س', 'offset': 1},
        {'code': 'USD', 'symbol': r'$', 'offset': 2},
      ];
      for (final vatConfig in vatAccountTemplates) {
        final currencyCode = vatConfig['code'] as String;
        final currencySymbol = vatConfig['symbol'] as String;
        final codeOffset = vatConfig['offset'] as int;
        final actualCode = (3300 + codeOffset).toString();
        final existing = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [actualCode, currencyCode], limit: 1);
        if (existing.isEmpty) {
          await db.insert('accounts', {
            'name_ar': 'ضريبة القيمة المضافة ($currencySymbol)',
            'name_en': 'VAT Payable ($currencyCode)',
            'account_code': actualCode,
            'account_type': 'LIABILITY',
            'balance': 0,
            'currency': currencyCode,
            'is_active': 1,
            'is_system': 1,
            'debt_ceiling': 0,
            'balance_type': 'credit',
            'created_at': now26,
            'updated_at': now26,
          });
        }
      }

      // ── Create stock_movements table if not exists ──
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_type ON stock_movements (movement_type)');
  }

  /// v27: Add cogs_account_id and vat_account_id to products
  static Future<void> migrateV27(Database db) async {
      try { await db.execute('ALTER TABLE products ADD COLUMN cogs_account_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN vat_account_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
  }

  /// v28: Ensure from_unit_id and to_unit_id in unit_conversions
  static Future<void> migrateV28(Database db) async {
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN from_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN to_unit_id INTEGER'); } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
  }

  /// v29: Create audit_trail table
  static Future<void> migrateV29(Database db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_trail (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          table_name TEXT NOT NULL,
          record_id INTEGER,
          record_type TEXT,
          old_values TEXT,
          new_values TEXT,
          user_name TEXT,
          shift_id INTEGER,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_trail_table ON audit_trail (table_name)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_trail_action ON audit_trail (action)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_trail_created ON audit_trail (created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_trail_record ON audit_trail (table_name, record_id)');
  }

  /// v30: Add variance column to stocktaking_items
  static Future<void> migrateV30(Database db) async {
      try {
        await db.execute('ALTER TABLE stocktaking_items ADD COLUMN variance REAL NOT NULL DEFAULT 0.0');
      } catch (e) { MigrationHelpers.logMigrationError("migration", e); }
  }
}
