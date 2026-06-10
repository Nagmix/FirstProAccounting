import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:firstpro/data/datasources/migrations/seeds.dart';
import 'package:firstpro/data/datasources/migrations/migration_helpers.dart';

class MigrationV2ToV10 {
  /// v2: Add item_code, supplier_id, and other product columns
  static Future<void> migrateV2(Database db) async {
    await db.execute('ALTER TABLE products ADD COLUMN item_code TEXT');
    await db.execute('ALTER TABLE products ADD COLUMN supplier_id INTEGER');
    await db.execute('ALTER TABLE products ADD COLUMN group_id TEXT');
    await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
    await db.execute(
        'ALTER TABLE products ADD COLUMN special_wholesale_price REAL NOT NULL DEFAULT 0.0');
    await db.execute(
        'ALTER TABLE products ADD COLUMN minimum_sale_price REAL NOT NULL DEFAULT 0.0');
    await db
        .execute('ALTER TABLE products ADD COLUMN sales_account_id INTEGER');
    await db
        .execute('ALTER TABLE products ADD COLUMN purchase_account_id INTEGER');
    await db.execute(
        'ALTER TABLE products ADD COLUMN inventory_account_id INTEGER');
    await db.execute('ALTER TABLE products ADD COLUMN warehouse_id INTEGER');
    await db.execute(
        'ALTER TABLE products ADD COLUMN weight REAL NOT NULL DEFAULT 0.0');
    await db.execute('ALTER TABLE products ADD COLUMN notes TEXT');
    await db.execute(
        'ALTER TABLE products ADD COLUMN include_in_reports INTEGER NOT NULL DEFAULT 1');
    await db
        .execute('CREATE INDEX idx_products_item_code ON products (item_code)');
  }

  /// v3: Create currencies table, add credit_limit to customers, seed currencies
  static Future<void> migrateV3(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS currencies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL UNIQUE,
          name_ar TEXT NOT NULL,
          name_en TEXT NOT NULL,
          symbol TEXT NOT NULL,
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          is_default INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_currencies_code ON currencies (code)');
    await db.execute(
        'ALTER TABLE customers ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0.0');
    await DatabaseSeeds.seedCurrencies(db);
  }

  /// v4: Add payment columns to invoices, create cash_boxes, seed default accounts
  static Future<void> migrateV4(Database db) async {
    // Add new columns to invoices
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN payment_mechanism TEXT NOT NULL DEFAULT \'cash\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN payment_method TEXT NOT NULL DEFAULT \'cash\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN is_return INTEGER NOT NULL DEFAULT 0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute('ALTER TABLE invoices ADD COLUMN cash_box_id INTEGER');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add balance_type to customers
    try {
      await db.execute(
          'ALTER TABLE customers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add balance_type to suppliers (default 'credit' because we typically owe the supplier)
    try {
      await db.execute(
          'ALTER TABLE suppliers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add linked_cash_box_id to accounts
    try {
      await db.execute(
          'ALTER TABLE accounts ADD COLUMN linked_cash_box_id INTEGER');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Change currency default in accounts
    try {
      await db.execute(
          'UPDATE accounts SET currency = \'YER\' WHERE currency = \'SAR\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'UPDATE suppliers SET currency = \'YER\' WHERE currency = \'SAR\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Create cash_boxes table
    await db.execute('''
        CREATE TABLE IF NOT EXISTS cash_boxes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'cash_box',
          bank_account_number TEXT,
          bank_name TEXT,
          bank_branch TEXT,
          balance REAL NOT NULL DEFAULT 0.0,
          balance_type TEXT NOT NULL DEFAULT 'credit',
          linked_account_id INTEGER,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (linked_account_id) REFERENCES accounts (id)
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_boxes_type ON cash_boxes (type)');

    // Migrate existing payment_type to new columns
    try {
      await db.execute(
          'UPDATE invoices SET payment_mechanism = payment_type WHERE payment_mechanism = \'cash\' AND payment_type IN (\'cash\', \'credit\')');
      await db.execute(
          'UPDATE invoices SET payment_method = \'cash\' WHERE payment_mechanism = \'cash\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Update default VAT rate
    try {
      await db
          .execute('UPDATE products SET tax_rate = 0.0 WHERE tax_rate = 15.0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Seed default accounts if not existing
    await DatabaseSeeds.seedDefaultAccounts(db);

    // Update or add YER currency, make it default
    try {
      final yerExists =
          await db.query('currencies', where: 'code = ?', whereArgs: ['YER']);
      if (yerExists.isEmpty) {
        await db.insert('currencies', {
          'code': 'YER',
          'name_ar': 'ريال يمني',
          'name_en': 'Yemeni Rial',
          'symbol': 'ر.ي',
          'exchange_rate': 1.0,
          'is_default': 1,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
        });
        await db.update('currencies', {'is_default': 0},
            where: 'code != ?', whereArgs: ['YER']);
      } else {
        await db.update('currencies', {'is_default': 1},
            where: 'code = ?', whereArgs: ['YER']);
        await db.update('currencies', {'is_default': 0},
            where: 'code != ?', whereArgs: ['YER']);
      }
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v5: Create expenses table, add currency to invoices/customers
  static Future<void> migrateV5(Database db) async {
    // Create expenses table
    await db.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          amount REAL NOT NULL DEFAULT 0.0,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          amount_base REAL NOT NULL DEFAULT 0.0,
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
          FOREIGN KEY (account_id) REFERENCES accounts (id)
        )
      ''');

    // Create expense indexes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses (category)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_expense_date ON expenses (expense_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_account_id ON expenses (account_id)');

    // Add currency column to invoices
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN currency TEXT NOT NULL DEFAULT \'YER\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add currency column to customers
    try {
      await db.execute(
          'ALTER TABLE customers ADD COLUMN currency TEXT NOT NULL DEFAULT \'YER\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v6: Create employees table, add transport_charges to invoices, seed accounts
  static Future<void> migrateV6(Database db) async {
    // Create employees table
    await db.execute('''
        CREATE TABLE IF NOT EXISTS employees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          job_title TEXT,
          balance REAL NOT NULL DEFAULT 0.0,
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

    // Add index on employees
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_employees_name ON employees (name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_employees_is_active ON employees (is_active)');

    // Add transport_charges column to invoices
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN transport_charges REAL NOT NULL DEFAULT 0.0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Delete AED and KWD currencies
    try {
      await db.delete('currencies',
          where: 'code IN (?, ?)', whereArgs: ['AED', 'KWD']);
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Seed accounts for SAR and USD currencies if they don't exist
    await DatabaseSeeds.seedAccountsForCurrency(db, 'YER', 'ر.ي', 0);
    await DatabaseSeeds.seedAccountsForCurrency(db, 'SAR', 'ر.س', 1);
    await DatabaseSeeds.seedAccountsForCurrency(db, 'USD', r'$', 2);
  }

  /// v7: Add e-wallet and bank transfer columns to invoices
  static Future<void> migrateV7(Database db) async {
    // Add e-wallet and bank transfer columns to invoices
    try {
      await db.execute('ALTER TABLE invoices ADD COLUMN ewallet_provider TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE invoices ADD COLUMN bank_transfer_provider TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute('ALTER TABLE invoices ADD COLUMN transfer_number TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute('ALTER TABLE invoices ADD COLUMN attachment_path TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v8: Add debt_ceiling, balance_type to accounts; add expense fields
  static Future<void> migrateV8(Database db) async {
    // Add debt_ceiling and balance_type to accounts
    try {
      await db.execute(
          'ALTER TABLE accounts ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE accounts ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add attachment_path, operation_type, expense_account_id to expenses
    try {
      await db.execute('ALTER TABLE expenses ADD COLUMN attachment_path TEXT');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE expenses ADD COLUMN operation_type TEXT NOT NULL DEFAULT \'صرف\'');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
    try {
      await db.execute(
          'ALTER TABLE expenses ADD COLUMN expense_account_id INTEGER');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }

    // Add index for expense_account_id
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_expenses_expense_account_id ON expenses (expense_account_id)');
    } catch (e) {
      MigrationHelpers.logMigrationError("migration", e);
    }
  }

  /// v9: Delete duplicate revenue and cost accounts
  static Future<void> migrateV9(Database db) async {
    // Delete duplicate-named accounts that have the same name as their parent category:
    // - حساب الإيرادات (codes 4000, 4001, 4002) under REVENUE
    // - حساب التكاليف (codes 3000, 3001, 3002) under COST
    // NOTE: حساب المصاريف (5000/5001/5002) and اجور النقل (5200/5201/5202) are NOT deleted
    // because they are required for expense and transport journal entries.
    final codesToDelete = [
      '4000', '4001', '4002', // حساب الإيرادات per currency
      '3000', '3001', '3002', // حساب التكاليف per currency
    ];
    for (final code in codesToDelete) {
      try {
        await db
            .delete('accounts', where: 'account_code = ?', whereArgs: [code]);
      } catch (e) {
        MigrationHelpers.logMigrationError("migration", e);
      }
    }
  }

  /// v10: Create quotation, purchase order, and sales order tables
  static Future<void> migrateV10(Database db) async {
    await db.execute('''
        CREATE TABLE IF NOT EXISTS quotations (
          id TEXT PRIMARY KEY,
          quotation_number TEXT NOT NULL,
          customer_id INTEGER,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          subtotal REAL NOT NULL DEFAULT 0.0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount REAL NOT NULL DEFAULT 0.0,
          tax_amount REAL NOT NULL DEFAULT 0.0,
          total REAL NOT NULL DEFAULT 0.0,
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
    await db.execute('''
        CREATE TABLE IF NOT EXISTS quotation_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quotation_id TEXT NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          description TEXT,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price REAL NOT NULL DEFAULT 0.0,
          total_price REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (quotation_id) REFERENCES quotations (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_orders (
          id TEXT PRIMARY KEY,
          order_number TEXT NOT NULL,
          supplier_id INTEGER,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          subtotal REAL NOT NULL DEFAULT 0.0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount REAL NOT NULL DEFAULT 0.0,
          tax_amount REAL NOT NULL DEFAULT 0.0,
          total REAL NOT NULL DEFAULT 0.0,
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
    await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_order_id TEXT NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          description TEXT,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price REAL NOT NULL DEFAULT 0.0,
          total_price REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_orders (
          id TEXT PRIMARY KEY,
          order_number TEXT NOT NULL,
          customer_id INTEGER,
          currency TEXT NOT NULL DEFAULT 'YER',
          exchange_rate REAL NOT NULL DEFAULT 1.0,
          subtotal REAL NOT NULL DEFAULT 0.0,
          discount_rate REAL NOT NULL DEFAULT 0.0,
          discount_amount REAL NOT NULL DEFAULT 0.0,
          tax_amount REAL NOT NULL DEFAULT 0.0,
          total REAL NOT NULL DEFAULT 0.0,
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
    await db.execute('''
        CREATE TABLE IF NOT EXISTS sales_order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sales_order_id TEXT NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          description TEXT,
          quantity REAL NOT NULL DEFAULT 1.0,
          unit_price REAL NOT NULL DEFAULT 0.0,
          total_price REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (sales_order_id) REFERENCES sales_orders (id),
          FOREIGN KEY (product_id) REFERENCES products (id)
        )
      ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotations_customer_id ON quotations (customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotations_status ON quotations (status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotation_items_quotation_id ON quotation_items (quotation_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON purchase_orders (supplier_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders (status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_purchase_order_items_po_id ON purchase_order_items (purchase_order_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_orders_customer_id ON sales_orders (customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_orders_status ON sales_orders (status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_order_items_so_id ON sales_order_items (sales_order_id)');
  }
}
