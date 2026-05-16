import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  static const int _databaseVersion = 8;
  static const String _databaseName = 'firstpro.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Accounts (Chart of Accounts)
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL,
        name_en TEXT NOT NULL DEFAULT '',
        parent_id INTEGER,
        account_code TEXT NOT NULL,
        account_type TEXT NOT NULL DEFAULT 'ASSET',
        balance REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'YER',
        linked_cash_box_id INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_system INTEGER NOT NULL DEFAULT 0,
        debt_ceiling REAL NOT NULL DEFAULT 0.0,
        balance_type TEXT NOT NULL DEFAULT 'credit',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES accounts (id)
      )
    ''');

    // Products
    await db.execute('''
      CREATE TABLE products (
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
        cost_price REAL NOT NULL DEFAULT 0.0,
        sell_price REAL NOT NULL DEFAULT 0.0,
        wholesale_price REAL NOT NULL DEFAULT 0.0,
        special_wholesale_price REAL NOT NULL DEFAULT 0.0,
        minimum_sale_price REAL NOT NULL DEFAULT 0.0,
        tax_rate REAL NOT NULL DEFAULT 0.0,
        sales_account_id INTEGER,
        purchase_account_id INTEGER,
        inventory_account_id INTEGER,
        current_stock REAL NOT NULL DEFAULT 0.0,
        min_stock REAL NOT NULL DEFAULT 0.0,
        warehouse_id INTEGER,
        expiry_date TEXT,
        expiry_tracking INTEGER NOT NULL DEFAULT 0,
        weight REAL NOT NULL DEFAULT 0.0,
        notes TEXT,
        include_in_reports INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        has_variants INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories (id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
        FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
      )
    ''');

    // Customers
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        address2 TEXT,
        email TEXT,
        gender TEXT,
        notification_method TEXT,
        notes TEXT,
        balance REAL NOT NULL DEFAULT 0.0,
        balance_type TEXT NOT NULL DEFAULT 'credit',
        country TEXT,
        credit_limit REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'YER',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Invoices
    await db.execute('''
      CREATE TABLE invoices (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payment_mechanism TEXT NOT NULL DEFAULT 'cash',
        payment_method TEXT NOT NULL DEFAULT 'cash',
        is_return INTEGER NOT NULL DEFAULT 0,
        cash_box_id INTEGER,
        customer_id INTEGER,
        supplier_id INTEGER,
        subtotal REAL NOT NULL DEFAULT 0.0,
        discount_rate REAL NOT NULL DEFAULT 0.0,
        discount_amount REAL NOT NULL DEFAULT 0.0,
        tax_amount REAL NOT NULL DEFAULT 0.0,
        total REAL NOT NULL DEFAULT 0.0,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        remaining REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'pending',
        cashier_id INTEGER,
        warehouse_id INTEGER,
        notes TEXT,
        currency TEXT NOT NULL DEFAULT 'YER',
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        transport_charges REAL NOT NULL DEFAULT 0.0,
        ewallet_provider TEXT,
        bank_transfer_provider TEXT,
        transfer_number TEXT,
        attachment_path TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
        FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id)
      )
    ''');

    // Invoice Items
    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1.0,
        unit_price REAL NOT NULL DEFAULT 0.0,
        total_price REAL NOT NULL DEFAULT 0.0,
        notes TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id),
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    // Transactions (Journal Entries)
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        journal_id INTEGER,
        debit REAL NOT NULL DEFAULT 0.0,
        credit REAL NOT NULL DEFAULT 0.0,
        description TEXT,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');

    // Cash Boxes and Banks
    await db.execute('''
      CREATE TABLE cash_boxes (
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

    // Categories
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        icon TEXT,
        color TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES categories (id)
      )
    ''');

    // Suppliers
    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        balance REAL NOT NULL DEFAULT 0.0,
        balance_type TEXT NOT NULL DEFAULT 'debit',
        currency TEXT NOT NULL DEFAULT 'YER',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Warehouses
    await db.execute('''
      CREATE TABLE warehouses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        location TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Users (Cashiers)
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'cashier',
        is_active INTEGER NOT NULL DEFAULT 1,
        last_login TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Notifications
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'general',
        reference_id TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Settings
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Currencies
    await db.execute('''
      CREATE TABLE currencies (
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

    // Expenses
    await db.execute('''
      CREATE TABLE expenses (
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

    // Employees
    await db.execute('''
      CREATE TABLE employees (
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

    // --- Indexes ---
    await db.execute('CREATE INDEX idx_products_barcode ON products (barcode)');
    await db.execute('CREATE INDEX idx_products_item_code ON products (item_code)');
    await db.execute('CREATE INDEX idx_invoices_customer_id ON invoices (customer_id)');
    await db.execute('CREATE INDEX idx_invoices_created_at ON invoices (created_at)');
    await db.execute('CREATE INDEX idx_invoices_status ON invoices (status)');
    await db.execute('CREATE INDEX idx_invoice_items_invoice_id ON invoice_items (invoice_id)');
    await db.execute('CREATE INDEX idx_transactions_account_id ON transactions (account_id)');
    await db.execute('CREATE INDEX idx_transactions_journal_id ON transactions (journal_id)');
    await db.execute('CREATE INDEX idx_transactions_date ON transactions (date)');
    await db.execute('CREATE INDEX idx_accounts_account_code ON accounts (account_code)');
    await db.execute('CREATE INDEX idx_accounts_account_type ON accounts (account_type)');
    await db.execute('CREATE INDEX idx_products_category_id ON products (category_id)');
    await db.execute('CREATE INDEX idx_currencies_code ON currencies (code)');
    await db.execute('CREATE INDEX idx_cash_boxes_type ON cash_boxes (type)');
    await db.execute('CREATE INDEX idx_expenses_category ON expenses (category)');
    await db.execute('CREATE INDEX idx_expenses_expense_date ON expenses (expense_date)');
    await db.execute('CREATE INDEX idx_expenses_account_id ON expenses (account_id)');
    await db.execute('CREATE INDEX idx_employees_name ON employees (name)');
    await db.execute('CREATE INDEX idx_employees_is_active ON employees (is_active)');
    await db.execute('CREATE INDEX idx_expenses_expense_account_id ON expenses (expense_account_id)');

    // Seed default data
    await _seedCurrencies(db);
    await _seedDefaultAccounts(db);
  }

  Future<void> _seedCurrencies(Database db) async {
    final now = DateTime.now().toIso8601String();
    final currencies = [
      {'code': 'YER', 'name_ar': 'ريال يمني', 'name_en': 'Yemeni Rial', 'symbol': 'ر.ي', 'exchange_rate': 1.0, 'is_default': 1, 'is_active': 1, 'created_at': now},
      {'code': 'SAR', 'name_ar': 'ريال سعودي', 'name_en': 'Saudi Riyal', 'symbol': 'ر.س', 'exchange_rate': 0.037, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'USD', 'name_ar': 'دولار أمريكي', 'name_en': 'US Dollar', 'symbol': r'$', 'exchange_rate': 0.004, 'is_default': 0, 'is_active': 1, 'created_at': now},
    ];
    for (final c in currencies) {
      await db.insert('currencies', c);
    }
  }

  Future<void> _seedDefaultAccounts(Database db) async {
    // Only seed if accounts don't already exist
    final existing = await db.query('accounts', where: 'account_code = ?', whereArgs: ['1000'], limit: 1);
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toIso8601String();

    // Helper to build account map
    Map<String, dynamic> makeAccount(String nameAr, String nameEn, String code, String type, String currency, String currencySymbol) {
      return {
        'name_ar': '$nameAr ($currencySymbol)',
        'name_en': '$nameEn ($currency)',
        'account_code': code,
        'account_type': type,
        'balance': 0.0,
        'currency': currency,
        'is_active': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      };
    }

    // Account templates: [nameAr, nameEn, baseCode, accountType]
    final templates = [
      ['حساب الأصول', 'Assets Account', '1000', 'ASSET'],
      ['حساب الصناديق والبنوك', 'Cash & Banks Account', '1100', 'ASSET'],
      ['حساب العملاء', 'Customers Account', '1200', 'ASSET'],
      ['حساب الخصوم', 'Liabilities Account', '2000', 'LIABILITY'],
      ['حساب الموردين', 'Suppliers Account', '2100', 'LIABILITY'],
      ['حساب التكاليف', 'Costs Account', '3000', 'COST'],
      ['حساب المشتريات', 'Purchases Account', '3100', 'COST'],
      ['حساب الإيرادات', 'Revenue Account', '4000', 'REVENUE'],
      ['حساب المبيعات', 'Sales Account', '4100', 'REVENUE'],
      ['حساب المصاريف', 'Expenses Account', '5000', 'EXPENSE'],
      ['حساب الموظفين', 'Employees Account', '5100', 'EXPENSE'],
      ['اجور النقل', 'Transport Charges', '5200', 'EXPENSE'],
    ];

    // Currency configurations: [currencyCode, symbol, codeOffset]
    final currencyConfigs = [
      ['YER', 'ر.ي', 0],
      ['SAR', 'ر.س', 1],
      ['USD', r'$', 2],
    ];

    for (final config in currencyConfigs) {
      final currencyCode = config[0] as String;
      final currencySymbol = config[1] as String;
      final codeOffset = config[2] as int;

      for (final template in templates) {
        final baseCode = int.parse(template[2] as String);
        final actualCode = (baseCode + codeOffset).toString();
        final account = makeAccount(
          template[0] as String,
          template[1] as String,
          actualCode,
          template[3] as String,
          currencyCode,
          currencySymbol,
        );
        await db.insert('accounts', account);
      }
    }
  }

  /// Seed accounts for a specific currency if they don't already exist.
  Future<void> _seedAccountsForCurrency(Database db, String currencyCode, String currencySymbol, int codeOffset) async {
    final now = DateTime.now().toIso8601String();

    // Check if accounts for this currency already exist
    final baseCode = 1000 + codeOffset;
    final existing = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [baseCode.toString(), currencyCode], limit: 1);
    if (existing.isNotEmpty) return;

    // Account templates: [nameAr, nameEn, baseCode, accountType]
    final templates = [
      ['حساب الأصول', 'Assets Account', 1000, 'ASSET'],
      ['حساب الصناديق والبنوك', 'Cash & Banks Account', 1100, 'ASSET'],
      ['حساب العملاء', 'Customers Account', 1200, 'ASSET'],
      ['حساب الخصوم', 'Liabilities Account', 2000, 'LIABILITY'],
      ['حساب الموردين', 'Suppliers Account', 2100, 'LIABILITY'],
      ['حساب التكاليف', 'Costs Account', 3000, 'COST'],
      ['حساب المشتريات', 'Purchases Account', 3100, 'COST'],
      ['حساب الإيرادات', 'Revenue Account', 4000, 'REVENUE'],
      ['حساب المبيعات', 'Sales Account', 4100, 'REVENUE'],
      ['حساب المصاريف', 'Expenses Account', 5000, 'EXPENSE'],
      ['حساب الموظفين', 'Employees Account', 5100, 'EXPENSE'],
      ['اجور النقل', 'Transport Charges', 5200, 'EXPENSE'],
    ];

    for (final template in templates) {
      final actualCode = ((template[2] as int) + codeOffset).toString();
      await db.insert('accounts', {
        'name_ar': '${template[0]} ($currencySymbol)',
        'name_en': '${template[1]} ($currencyCode)',
        'account_code': actualCode,
        'account_type': template[3] as String,
        'balance': 0.0,
        'currency': currencyCode,
        'is_active': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN item_code TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN supplier_id INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN group_id TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN special_wholesale_price REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE products ADD COLUMN minimum_sale_price REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE products ADD COLUMN sales_account_id INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN purchase_account_id INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN inventory_account_id INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN warehouse_id INTEGER');
      await db.execute('ALTER TABLE products ADD COLUMN weight REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE products ADD COLUMN notes TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN include_in_reports INTEGER NOT NULL DEFAULT 1');
      await db.execute('CREATE INDEX idx_products_item_code ON products (item_code)');
    }
    if (oldVersion < 3) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_currencies_code ON currencies (code)');
      await db.execute('ALTER TABLE customers ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0.0');
      await _seedCurrencies(db);
    }
    if (oldVersion < 4) {
      // Add new columns to invoices
      try { await db.execute('ALTER TABLE invoices ADD COLUMN payment_mechanism TEXT NOT NULL DEFAULT \'cash\''); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN payment_method TEXT NOT NULL DEFAULT \'cash\''); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN is_return INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN cash_box_id INTEGER'); } catch (_) {}

      // Add balance_type to customers
      try { await db.execute('ALTER TABLE customers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\''); } catch (_) {}

      // Add balance_type to suppliers
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'debit\''); } catch (_) {}

      // Add linked_cash_box_id to accounts
      try { await db.execute('ALTER TABLE accounts ADD COLUMN linked_cash_box_id INTEGER'); } catch (_) {}

      // Change currency default in accounts
      try { await db.execute('UPDATE accounts SET currency = \'YER\' WHERE currency = \'SAR\''); } catch (_) {}
      try { await db.execute('UPDATE suppliers SET currency = \'YER\' WHERE currency = \'SAR\''); } catch (_) {}

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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_boxes_type ON cash_boxes (type)');

      // Migrate existing payment_type to new columns
      try {
        await db.execute('UPDATE invoices SET payment_mechanism = payment_type WHERE payment_mechanism = \'cash\' AND payment_type IN (\'cash\', \'credit\')');
        await db.execute('UPDATE invoices SET payment_method = \'cash\' WHERE payment_mechanism = \'cash\'');
      } catch (_) {}

      // Update default VAT rate
      try { await db.execute('UPDATE products SET tax_rate = 0.0 WHERE tax_rate = 15.0'); } catch (_) {}

      // Seed default accounts if not existing
      await _seedDefaultAccounts(db);

      // Update or add YER currency, make it default
      try {
        final yerExists = await db.query('currencies', where: 'code = ?', whereArgs: ['YER']);
        if (yerExists.isEmpty) {
          await db.insert('currencies', {
            'code': 'YER', 'name_ar': 'ريال يمني', 'name_en': 'Yemeni Rial',
            'symbol': 'ر.ي', 'exchange_rate': 1.0, 'is_default': 1, 'is_active': 1,
            'created_at': DateTime.now().toIso8601String(),
          });
          await db.update('currencies', {'is_default': 0}, where: 'code != ?', whereArgs: ['YER']);
        } else {
          await db.update('currencies', {'is_default': 1}, where: 'code = ?', whereArgs: ['YER']);
          await db.update('currencies', {'is_default': 0}, where: 'code != ?', whereArgs: ['YER']);
        }
      } catch (_) {}
    }
    if (oldVersion < 5) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses (category)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_expense_date ON expenses (expense_date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_account_id ON expenses (account_id)');

      // Add currency column to invoices
      try { await db.execute('ALTER TABLE invoices ADD COLUMN currency TEXT NOT NULL DEFAULT \'YER\''); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0'); } catch (_) {}

      // Add currency column to customers
      try { await db.execute('ALTER TABLE customers ADD COLUMN currency TEXT NOT NULL DEFAULT \'YER\''); } catch (_) {}
    }
    if (oldVersion < 6) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_employees_name ON employees (name)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_employees_is_active ON employees (is_active)');

      // Add transport_charges column to invoices
      try { await db.execute('ALTER TABLE invoices ADD COLUMN transport_charges REAL NOT NULL DEFAULT 0.0'); } catch (_) {}

      // Delete AED and KWD currencies
      try { await db.delete('currencies', where: 'code IN (?, ?)', whereArgs: ['AED', 'KWD']); } catch (_) {}

      // Seed accounts for SAR and USD currencies if they don't exist
      await _seedAccountsForCurrency(db, 'YER', 'ر.ي', 0);
      await _seedAccountsForCurrency(db, 'SAR', 'ر.س', 1);
      await _seedAccountsForCurrency(db, 'USD', r'$', 2);
    }
    if (oldVersion < 7) {
      // Add e-wallet and bank transfer columns to invoices
      try { await db.execute('ALTER TABLE invoices ADD COLUMN ewallet_provider TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN bank_transfer_provider TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN transfer_number TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN attachment_path TEXT'); } catch (_) {}
    }
    if (oldVersion < 8) {
      // Add debt_ceiling and balance_type to accounts
      try { await db.execute('ALTER TABLE accounts ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (_) {}
      try { await db.execute('ALTER TABLE accounts ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\''); } catch (_) {}

      // Add attachment_path, operation_type, expense_account_id to expenses
      try { await db.execute('ALTER TABLE expenses ADD COLUMN attachment_path TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE expenses ADD COLUMN operation_type TEXT NOT NULL DEFAULT \'صرف\''); } catch (_) {}
      try { await db.execute('ALTER TABLE expenses ADD COLUMN expense_account_id INTEGER'); } catch (_) {}

      // Add index for expense_account_id
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_expense_account_id ON expenses (expense_account_id)'); } catch (_) {}
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Product CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertProduct(Map<String, dynamic> productMap) async {
    final db = await database;
    return await db.insert('products', productMap);
  }

  Future<List<Map<String, dynamic>>> getAllProducts({bool? activeOnly, String orderBy = 'created_at DESC'}) async {
    final db = await database;
    if (activeOnly == true) {
      return await db.query('products', where: 'is_active = ?', whereArgs: [1], orderBy: orderBy);
    }
    return await db.query('products', orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> searchProducts(String query, {int? warehouseId}) async {
    final db = await database;
    final likeQuery = '%$query%';
    if (warehouseId != null) {
      return await db.query(
        'products',
        where: '(name_ar LIKE ? OR name_en LIKE ? OR barcode LIKE ? OR item_code LIKE ?) AND (warehouse_id = ? OR warehouse_id IS NULL) AND is_active = 1',
        whereArgs: [likeQuery, likeQuery, likeQuery, likeQuery, warehouseId],
        orderBy: 'created_at DESC',
      );
    }
    return await db.query(
      'products',
      where: 'name_ar LIKE ? OR name_en LIKE ? OR barcode LIKE ? OR item_code LIKE ?',
      whereArgs: [likeQuery, likeQuery, likeQuery, likeQuery],
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getProductById(int id) async {
    final db = await database;
    final results = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateProduct(int id, Map<String, dynamic> productMap) async {
    final db = await database;
    return await db.update('products', productMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getProductCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM products');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<String> getNextItemCode() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(item_code, 5) AS INTEGER)), 0) + 1 AS next_code FROM products WHERE item_code LIKE 'PRD-%'",
    );
    final nextNum = (result.first['next_code'] as num?)?.toInt() ?? 1;
    return 'PRD-${nextNum.toString().padLeft(5, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Customer CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCustomer(Map<String, dynamic> customerMap) async {
    final db = await database;
    return await db.insert('customers', customerMap);
  }

  Future<List<Map<String, dynamic>>> getAllCustomers({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.query('customers', orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    final db = await database;
    final likeQuery = '%$query%';
    return await db.query('customers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: [likeQuery, likeQuery], orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final db = await database;
    final results = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCustomer(int id, Map<String, dynamic> customerMap) async {
    final db = await database;
    return await db.update('customers', customerMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Supplier CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllSuppliers() async {
    final db = await database;
    return await db.query('suppliers', orderBy: 'name ASC');
  }

  Future<int> insertSupplier(Map<String, dynamic> supplierMap) async {
    final db = await database;
    return await db.insert('suppliers', supplierMap);
  }

  Future<int> updateSupplier(int id, Map<String, dynamic> supplierMap) async {
    final db = await database;
    return await db.update('suppliers', supplierMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSupplier(int id) async {
    final db = await database;
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Cash Boxes & Banks CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCashBox(Map<String, dynamic> cashBoxMap) async {
    final db = await database;
    return await db.insert('cash_boxes', cashBoxMap);
  }

  Future<List<Map<String, dynamic>>> getAllCashBoxes() async {
    final db = await database;
    return await db.query('cash_boxes', where: 'is_active = ?', whereArgs: [1], orderBy: 'type ASC, name ASC');
  }

  Future<List<Map<String, dynamic>>> getCashBoxesByType(String type) async {
    final db = await database;
    return await db.query('cash_boxes', where: 'type = ? AND is_active = ?', whereArgs: [type, 1], orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getCashBoxById(int id) async {
    final db = await database;
    final results = await db.query('cash_boxes', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCashBox(int id, Map<String, dynamic> cashBoxMap) async {
    final db = await database;
    return await db.update('cash_boxes', cashBoxMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCashBox(int id) async {
    final db = await database;
    return await db.delete('cash_boxes', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalCashBalance() async {
    final db = await database;
    final result = await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN balance_type = 'credit' THEN balance ELSE -balance END), 0.0) AS total FROM cash_boxes WHERE is_active = 1");
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ══════════════════════════════════════════════════════════════
  //  Currency CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCurrency(Map<String, dynamic> currencyMap) async {
    final db = await database;
    return await db.insert('currencies', currencyMap);
  }

  Future<List<Map<String, dynamic>>> getAllCurrencies({String orderBy = 'is_default DESC, code ASC'}) async {
    final db = await database;
    return await db.query('currencies', orderBy: orderBy);
  }

  Future<Map<String, dynamic>?> getDefaultCurrency() async {
    final db = await database;
    final results = await db.query('currencies', where: 'is_default = ?', whereArgs: [1], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateCurrency(int id, Map<String, dynamic> currencyMap) async {
    final db = await database;
    return await db.update('currencies', currencyMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCurrency(int id) async {
    final db = await database;
    return await db.delete('currencies', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setDefaultCurrency(int id) async {
    final db = await database;
    await db.update('currencies', {'is_default': 0});
    await db.update('currencies', {'is_default': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Invoice CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertInvoiceWithItems(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('invoices', invoiceMap);
      for (final item in items) {
        await txn.insert('invoice_items', item);
      }
    });
  }

  /// Save invoice and post journal entries to the chart of accounts.
  /// [transportCharges] - optional transport charges that generate additional journal entries.
  Future<void> saveInvoiceWithJournalEntries(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items, {
    required String invoiceType,
    required String paymentMechanism,
    required bool isReturn,
    int? cashBoxId,
    double transportCharges = 0.0,
  }) async {
    final db = await database;
    final total = (invoiceMap['total'] as num?)?.toDouble() ?? 0.0;
    final invoiceCurrency = (invoiceMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Insert invoice
      await txn.insert('invoices', invoiceMap);

      // Insert invoice items
      for (final item in items) {
        await txn.insert('invoice_items', item);
      }

      // Post journal entries
      final journalId = DateTime.now().millisecondsSinceEpoch;

      // Determine currency-specific account code offsets
      final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

      // Get account IDs for journal entries (currency-specific)
      final salesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(4100 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final purchasesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), invoiceCurrency], limit: 1);

      final salesAccountId = salesAccount.isNotEmpty ? salesAccount.first['id'] as int : null;
      final purchasesAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;
      final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
      final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
      final cashBanksAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;

      // Use specific cash box account if available
      int? debitAccountId;
      int? creditAccountId;

      if (invoiceType == 'sale' || invoiceType == 'sale_return') {
        if (isReturn) {
          // Sale Return: Debit Sales Revenue, Credit Customer/Cash
          debitAccountId = salesAccountId;
          creditAccountId = paymentMechanism == 'credit' ? customersAccountId : (cashBoxId != null ? cashBanksAccountId : cashBanksAccountId);
        } else {
          // Sale: Debit Customer/Cash, Credit Sales Revenue
          debitAccountId = paymentMechanism == 'credit' ? customersAccountId : (cashBoxId != null ? cashBanksAccountId : cashBanksAccountId);
          creditAccountId = salesAccountId;
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        if (isReturn) {
          // Purchase Return: Debit Cash/Supplier, Credit Purchases
          debitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : (cashBoxId != null ? cashBanksAccountId : cashBanksAccountId);
          creditAccountId = purchasesAccountId;
        } else {
          // Purchase: Debit Purchases, Credit Cash/Supplier
          debitAccountId = purchasesAccountId;
          creditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : (cashBoxId != null ? cashBanksAccountId : cashBanksAccountId);
        }
      }

      if (debitAccountId != null && total > 0) {
        await txn.insert('transactions', {
          'account_id': debitAccountId,
          'journal_id': journalId,
          'debit': total,
          'credit': 0.0,
          'description': '${invoiceMap['type'] == 'sale' ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - ${invoiceMap['id']}',
          'date': now,
          'created_at': now,
        });
      }

      if (creditAccountId != null && total > 0) {
        await txn.insert('transactions', {
          'account_id': creditAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': total,
          'description': '${invoiceMap['type'] == 'sale' ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - ${invoiceMap['id']}',
          'date': now,
          'created_at': now,
        });
      }

      // Update account balances
      if (debitAccountId != null) {
        await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [total, now, debitAccountId]);
      }
      if (creditAccountId != null) {
        await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [total, now, creditAccountId]);
      }

      // ── Transport Charges Journal Entries ──
      if (transportCharges > 0) {
        final transportAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(5200 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final transportAccountId = transportAccount.isNotEmpty ? transportAccount.first['id'] as int : null;

        if (invoiceType == 'sale' || invoiceType == 'sale_return') {
          // Sales with transport: Debit customer/cash (transport), Credit transport expense
          final transportDebitId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          final transportCreditId = transportAccountId;

          if (transportDebitId != null) {
            await txn.insert('transactions', {
              'account_id': transportDebitId,
              'journal_id': journalId,
              'debit': transportCharges,
              'credit': 0.0,
              'description': 'اجور نقل - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [transportCharges, now, transportDebitId]);
          }
          if (transportCreditId != null) {
            await txn.insert('transactions', {
              'account_id': transportCreditId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': transportCharges,
              'description': 'اجور نقل - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, transportCreditId]);
          }
        } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
          // Purchases with transport: Debit transport expense, Credit cash/supplier
          final transportDebitId = transportAccountId;
          final transportCreditId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;

          if (transportDebitId != null) {
            await txn.insert('transactions', {
              'account_id': transportDebitId,
              'journal_id': journalId,
              'debit': transportCharges,
              'credit': 0.0,
              'description': 'اجور نقل - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [transportCharges, now, transportDebitId]);
          }
          if (transportCreditId != null) {
            await txn.insert('transactions', {
              'account_id': transportCreditId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': transportCharges,
              'description': 'اجور نقل - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, transportCreditId]);
          }
        }

        // Update cash box for transport charges (cash payments)
        if (cashBoxId != null) {
          if (invoiceType == 'sale' || invoiceType == 'sale_return') {
            // Sale: transport charges increase cash received
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [transportCharges, now, cashBoxId]);
          } else {
            // Purchase: transport charges decrease cash
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, cashBoxId]);
          }
        }
      }

      // Update customer/supplier balance
      if (invoiceMap['customer_id'] != null) {
        final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
        final totalWithTransport = total + (transportCharges > 0 && paymentMechanism == 'credit' && (invoiceType == 'sale' || invoiceType == 'sale_return') ? transportCharges : 0);
        if (isDebit) {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoiceMap['customer_id']]);
        } else {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoiceMap['customer_id']]);
        }
      }

      // Supplier balance logic:
      // Purchase (not return): supplier has credit balance (له) → balance increases
      // Purchase return: supplier balance decreases
      if (invoiceMap['supplier_id'] != null) {
        final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
        final totalWithTransport = total + (transportCharges > 0 && paymentMechanism == 'credit' && (invoiceType == 'purchase' || invoiceType == 'purchase_return') ? transportCharges : 0);
        if (isCreditToSupplier) {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoiceMap['supplier_id']]);
        } else {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoiceMap['supplier_id']]);
        }
      }

      // Update cash box balance (for invoice total, excluding transport which is handled above)
      if (cashBoxId != null) {
        final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase_return' && !isReturn);
        if (isCashIn) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [total, now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [total, now, cashBoxId]);
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllInvoices({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT i.*,
        CASE
          WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل')
          WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد')
          ELSE 'بدون عميل'
        END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      ORDER BY i.$orderBy
    ''');
  }

  Future<List<Map<String, dynamic>>> getInvoicesByType(String type) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT i.*,
        CASE
          WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل')
          WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد')
          ELSE 'بدون عميل'
        END AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      WHERE i.type = ?
      ORDER BY i.created_at DESC
    ''', [type]);
  }

  Future<List<Map<String, dynamic>>> getInvoiceItems(String invoiceId) async {
    final db = await database;
    return await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
  }

  Future<int> deleteInvoice(String id) async {
    final db = await database;
    await db.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
    return await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Expense CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertExpense(Map<String, dynamic> expenseMap) async {
    final db = await database;
    return await db.insert('expenses', expenseMap);
  }

  Future<List<Map<String, dynamic>>> getAllExpenses({String orderBy = 'expense_date DESC'}) async {
    final db = await database;
    return await db.query('expenses', orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory(String category) async {
    final db = await database;
    return await db.query('expenses', where: 'category = ?', whereArgs: [category], orderBy: 'expense_date DESC');
  }

  Future<List<Map<String, dynamic>>> getExpensesByDateRange(String startDate, String endDate) async {
    final db = await database;
    return await db.query('expenses', where: 'expense_date >= ? AND expense_date <= ?', whereArgs: [startDate, endDate], orderBy: 'expense_date DESC');
  }

  Future<Map<String, dynamic>?> getExpenseById(int id) async {
    final db = await database;
    final results = await db.query('expenses', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateExpense(int id, Map<String, dynamic> expenseMap) async {
    final db = await database;
    return await db.update('expenses', expenseMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalExpensesThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery("SELECT COALESCE(SUM(amount_base), 0.0) AS total FROM expenses WHERE date(expense_date) >= ?", [monthStart]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalExpensesByCategory(String category) async {
    final db = await database;
    final result = await db.rawQuery("SELECT COALESCE(SUM(amount_base), 0.0) AS total FROM expenses WHERE category = ?", [category]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalExpensesForDate(DateTime date) async {
    final db = await database;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT COALESCE(SUM(amount_base), 0.0) AS total FROM expenses WHERE date(expense_date) = ?", [dateStr]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Save expense with journal entry: Debit expense account, Credit cash/bank.
  Future<void> saveExpenseWithJournalEntry(Map<String, dynamic> expenseMap) async {
    final db = await database;
    final amountBase = (expenseMap['amount_base'] as num?)?.toDouble() ?? 0.0;
    final expenseCurrency = (expenseMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Insert expense
      await txn.insert('expenses', expenseMap);

      // Post journal entry
      final journalId = DateTime.now().millisecondsSinceEpoch;

      // Determine currency-specific account code offset
      final codeOffset = expenseCurrency == 'SAR' ? 1 : (expenseCurrency == 'USD' ? 2 : 0);

      // Get expense account (code 5000+offset) or use provided account_id
      final expenseAccountId = expenseMap['account_id'] as int?;
      int? debitAccountId = expenseAccountId;

      if (debitAccountId == null) {
        final expenseAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(5000 + codeOffset).toString(), expenseCurrency], limit: 1);
        debitAccountId = expenseAccount.isNotEmpty ? expenseAccount.first['id'] as int : null;
      }

      // Get cash/bank account (code 1100+offset) or use cash box linked account
      int? creditAccountId;
      final cashBoxId = expenseMap['cash_box_id'] as int?;
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final linkedAccountId = cashBox.first['linked_account_id'] as int?;
          if (linkedAccountId != null) {
            creditAccountId = linkedAccountId;
          }
        }
      }
      if (creditAccountId == null) {
        final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), expenseCurrency], limit: 1);
        creditAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
      }

      final title = expenseMap['title'] as String? ?? 'مصروف';

      // Debit expense account
      if (debitAccountId != null && amountBase > 0) {
        await txn.insert('transactions', {
          'account_id': debitAccountId,
          'journal_id': journalId,
          'debit': amountBase,
          'credit': 0.0,
          'description': 'مصروف: $title',
          'date': now,
          'created_at': now,
        });
      }

      // Credit cash/bank account
      if (creditAccountId != null && amountBase > 0) {
        await txn.insert('transactions', {
          'account_id': creditAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': amountBase,
          'description': 'مصروف: $title',
          'date': now,
          'created_at': now,
        });
      }

      // Update account balances
      if (debitAccountId != null) {
        await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [amountBase, now, debitAccountId]);
      }
      if (creditAccountId != null) {
        await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [amountBase, now, creditAccountId]);
      }

      // Update cash box balance
      if (cashBoxId != null && amountBase > 0) {
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [amountBase, now, cashBoxId]);
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  Expense Account methods
  // ══════════════════════════════════════════════════════════════

  /// Get all expense accounts (accounts with type='EXPENSE')
  Future<List<Map<String, dynamic>>> getExpenseAccounts() async {
    final db = await database;
    return await db.query('accounts', where: 'is_active = ? AND account_type = ?', whereArgs: [1, 'EXPENSE'], orderBy: 'account_code ASC');
  }

  /// Get all expenses for a specific expense account
  Future<List<Map<String, dynamic>>> getExpensesByAccountId(int accountId, {String orderBy = 'expense_date DESC'}) async {
    final db = await database;
    return await db.query('expenses', where: 'expense_account_id = ?', whereArgs: [accountId], orderBy: orderBy);
  }

  /// Get all transactions for an account with running balance calculated
  Future<List<Map<String, dynamic>>> getAccountTransactions(int accountId) async {
    final db = await database;
    return await db.query('transactions', where: 'account_id = ?', whereArgs: [accountId], orderBy: 'date ASC, id ASC');
  }

  /// Get current balance of an account (computed from transactions)
  Future<double> getAccountBalance(int accountId) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(debit) - SUM(credit), 0.0) AS balance FROM transactions WHERE account_id = ?",
      [accountId],
    );
    return (result.first['balance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Create an expense account with optional opening balance
  Future<int> createExpenseAccount({
    required String nameAr,
    required String currency,
    double? debtCeiling,
    double openingBalance = 0.0,
    String balanceType = 'credit', // 'credit' = له, 'debit' = عليه
    String? notes,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Get next account code for EXPENSE type
    final codeOffset = currency == 'SAR' ? 1 : (currency == 'USD' ? 2 : 0);
    final currencySymbol = currency == 'SAR' ? 'ر.س' : (currency == 'USD' ? r'$' : 'ر.ي');

    // Find the max existing expense account code for this currency
    final existingExpenseAccounts = await db.query(
      'accounts',
      where: 'account_type = ? AND currency = ?',
      whereArgs: ['EXPENSE', currency],
      orderBy: 'account_code DESC',
      limit: 1,
    );

    String newCode;
    if (existingExpenseAccounts.isNotEmpty) {
      final lastCode = int.tryParse(existingExpenseAccounts.first['account_code'] as String) ?? 5000;
      newCode = (lastCode + 1).toString();
    } else {
      newCode = (5000 + codeOffset).toString();
    }

    // Create the account
    final accountId = await db.insert('accounts', {
      'name_ar': '$nameAr ($currencySymbol)',
      'name_en': nameAr,
      'account_code': newCode,
      'account_type': 'EXPENSE',
      'balance': openingBalance,
      'currency': currency,
      'is_active': 1,
      'is_system': 0,
      'debt_ceiling': debtCeiling ?? 0.0,
      'balance_type': balanceType,
      'created_at': now,
      'updated_at': now,
    });

    // Create opening balance transaction if > 0
    if (openingBalance > 0) {
      final journalId = DateTime.now().millisecondsSinceEpoch;
      if (balanceType == 'credit') {
        // له (credit) - the account has credit balance
        await db.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': openingBalance,
          'description': 'رصيد افتتاحي - $nameAr',
          'date': now,
          'created_at': now,
        });
      } else {
        // عليه (debit) - the account has debit balance
        await db.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': openingBalance,
          'credit': 0.0,
          'description': 'رصيد افتتاحي - $nameAr',
          'date': now,
          'created_at': now,
        });
      }
    }

    return accountId;
  }

  // ══════════════════════════════════════════════════════════════
  //  Category methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllCategories() async {
    final db = await database;
    return await db.query('categories', where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
  }

  Future<int> insertCategory(Map<String, dynamic> categoryMap) async {
    final db = await database;
    return await db.insert('categories', categoryMap);
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Warehouse methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllWarehouses() async {
    final db = await database;
    return await db.query('warehouses', where: 'is_active = ?', whereArgs: [1], orderBy: 'name ASC');
  }

  Future<int> insertWarehouse(Map<String, dynamic> warehouseMap) async {
    final db = await database;
    return await db.insert('warehouses', warehouseMap);
  }

  Future<int> updateWarehouse(int id, Map<String, dynamic> warehouseMap) async {
    final db = await database;
    return await db.update('warehouses', warehouseMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWarehouse(int id) async {
    final db = await database;
    return await db.delete('warehouses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchWarehouses(String query) async {
    final db = await database;
    final likeQuery = '%$query%';
    return await db.query(
      'warehouses',
      where: 'is_active = ? AND (name LIKE ? OR location LIKE ?)',
      whereArgs: [1, likeQuery, likeQuery],
      orderBy: 'name ASC',
    );
  }

  Future<int> getProductCountByWarehouse(int warehouseId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM products WHERE warehouse_id = ? AND is_active = 1',
      [warehouseId],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  // ══════════════════════════════════════════════════════════════
  //  Account methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await database;
    return await db.query('accounts', where: 'is_active = ?', whereArgs: [1], orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsByType(String accountType) async {
    final db = await database;
    return await db.query('accounts', where: 'is_active = ? AND account_type = ?', whereArgs: [1, accountType], orderBy: 'account_code ASC');
  }

  Future<List<Map<String, dynamic>>> getAccountsByCurrency(String currencyCode) async {
    final db = await database;
    return await db.query('accounts', where: 'is_active = ? AND currency = ?', whereArgs: [1, currencyCode], orderBy: 'account_code ASC');
  }

  Future<int> insertAccount(Map<String, dynamic> accountMap) async {
    final db = await database;
    return await db.insert('accounts', accountMap);
  }

  Future<int> updateAccount(int id, Map<String, dynamic> accountMap) async {
    final db = await database;
    return await db.update('accounts', accountMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    // Check if it's a system account
    final account = await db.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (account.isNotEmpty && (account.first['is_system'] as int?) == 1) {
      return -1; // Cannot delete system account
    }
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextAccountCode(String accountType) async {
    final db = await database;
    final prefixMap = {
      'ASSET': '1',
      'LIABILITY': '2',
      'COST': '3',
      'REVENUE': '4',
      'EXPENSE': '5',
    };
    final prefix = prefixMap[accountType] ?? '9';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(account_code, 2) AS INTEGER)), 0) + 1 AS next_code FROM accounts WHERE account_code LIKE '$prefix%' AND account_type = ?",
      [accountType],
    );
    final nextNum = (result.first['next_code'] as num?)?.toInt() ?? int.parse('${prefix}001');
    return nextNum.toString().padLeft(4, '0');
  }

  // ══════════════════════════════════════════════════════════════
  //  Employee CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertEmployee(Map<String, dynamic> employeeMap) async {
    final db = await database;
    return await db.insert('employees', employeeMap);
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async {
    final db = await database;
    return await db.query('employees', orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getEmployeeById(int id) async {
    final db = await database;
    final results = await db.query('employees', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateEmployee(int id, Map<String, dynamic> employeeMap) async {
    final db = await database;
    return await db.update('employees', employeeMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteEmployee(int id) async {
    final db = await database;
    return await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Settings methods
  // ══════════════════════════════════════════════════════════════

  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value, 'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ══════════════════════════════════════════════════════════════
  //  Dashboard query methods
  // ══════════════════════════════════════════════════════════════

  Future<double> getTotalSalesForDate(DateTime date) async {
    final db = await database;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('sale', 'sale_return') AND is_return = 0 AND date(created_at) = ?", [dateStr]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalPurchasesThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('purchase', 'purchase_return') AND is_return = 0 AND date(created_at) >= ?", [monthStart]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalSalesThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('sale', 'sale_return') AND is_return = 0 AND date(created_at) >= ?", [monthStart]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> getInvoiceCountForDate(DateTime date) async {
    final db = await database;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT COUNT(*) AS cnt FROM invoices WHERE date(created_at) = ?", [dateStr]);
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<int> getCustomerCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM customers');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> getCashBalance() async {
    return getTotalCashBalance();
  }

  Future<List<Map<String, dynamic>>> getRecentInvoices({int limit = 5}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT i.id, i.type, i.total, i.paid_amount, i.remaining, i.is_return,
             i.status, i.created_at, i.payment_mechanism,
             COALESCE(c.name, s.name, 'بدون عميل') AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      ORDER BY i.created_at DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getDailySalesTotals({int days = 7}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type IN ('sale', 'sale_return') AND is_return = 0 AND date(created_at) >= ?
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Additional utility methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getTransactionsByAccount(int accountId) async {
    final db = await database;
    return await db.query('transactions', where: 'account_id = ?', whereArgs: [accountId], orderBy: 'date DESC');
  }

  Future<Map<String, dynamic>?> getSupplierById(int id) async {
    final db = await database;
    final results = await db.query('suppliers', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  // ══════════════════════════════════════════════════════════════
  //  Notification CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertNotification(Map<String, dynamic> notificationMap) async {
    final db = await database;
    return await db.insert('notifications', notificationMap);
  }

  Future<List<Map<String, dynamic>>> getAllNotifications({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.query('notifications', orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> getNotificationsByType(String type, {String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.query('notifications', where: 'type = ?', whereArgs: [type], orderBy: orderBy);
  }

  Future<int> markNotificationAsRead(int id) async {
    final db = await database;
    return await db.update('notifications', {'is_read': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteNotification(int id) async {
    final db = await database;
    return await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }
}
