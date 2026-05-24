import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static const int _databaseVersion = 17;
  static const String _databaseName = 'firstpro.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _databaseFuture ??= initDatabase();
    _database = await _databaseFuture!;
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
        image_path TEXT,
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

    // Invoices (v12: includes shift_id, cashier_name, is_posted)
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
        shift_id INTEGER,
        cashier_name TEXT,
        is_posted INTEGER NOT NULL DEFAULT 0,
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
        currency TEXT NOT NULL DEFAULT 'YER',
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


    // Quotations
    await db.execute('''
      CREATE TABLE quotations (
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

    // Quotation Items
    await db.execute('''
      CREATE TABLE quotation_items (
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

    // Purchase Orders
    await db.execute('''
      CREATE TABLE purchase_orders (
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

    // Purchase Order Items
    await db.execute('''
      CREATE TABLE purchase_order_items (
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

    // Sales Orders
    await db.execute('''
      CREATE TABLE sales_orders (
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

    // Sales Order Items
    await db.execute('''
      CREATE TABLE sales_order_items (
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


    // Shifts (الورديات)
    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_number TEXT NOT NULL,
        cashier_id INTEGER,
        cashier_name TEXT,
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

    // Currency Exchanges (صرافة العملات) - v12
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

    // Cash Transfers (تحويل بين الصناديق) - v12
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

    await db.execute('CREATE INDEX idx_shifts_cashier_id ON shifts (cashier_id)');
    await db.execute('CREATE INDEX idx_shifts_cash_box_id ON shifts (cash_box_id)');
    await db.execute('CREATE INDEX idx_shifts_status ON shifts (status)');
    // --- Indexes ---
    await db.execute('CREATE INDEX idx_products_barcode ON products (barcode)');
    await db.execute('CREATE INDEX idx_products_item_code ON products (item_code)');
    await db.execute('CREATE INDEX idx_invoices_customer_id ON invoices (customer_id)');
    await db.execute('CREATE INDEX idx_invoices_created_at ON invoices (created_at)');
    await db.execute('CREATE INDEX idx_invoices_status ON invoices (status)');
    await db.execute('CREATE INDEX idx_invoices_shift_id ON invoices (shift_id)');
    await db.execute('CREATE INDEX idx_invoices_is_posted ON invoices (is_posted)');
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
    await db.execute('CREATE INDEX idx_quotations_customer_id ON quotations (customer_id)');
    await db.execute('CREATE INDEX idx_quotations_status ON quotations (status)');
    await db.execute('CREATE INDEX idx_quotation_items_quotation_id ON quotation_items (quotation_id)');
    await db.execute('CREATE INDEX idx_purchase_orders_supplier_id ON purchase_orders (supplier_id)');
    await db.execute('CREATE INDEX idx_purchase_orders_status ON purchase_orders (status)');
    await db.execute('CREATE INDEX idx_purchase_order_items_po_id ON purchase_order_items (purchase_order_id)');
    await db.execute('CREATE INDEX idx_sales_orders_customer_id ON sales_orders (customer_id)');
    await db.execute('CREATE INDEX idx_sales_orders_status ON sales_orders (status)');
    await db.execute('CREATE INDEX idx_sales_order_items_so_id ON sales_order_items (sales_order_id)');
    // v12 indexes
    await db.execute('CREATE INDEX idx_currency_exchanges_number ON currency_exchanges (exchange_number)');
    await db.execute('CREATE INDEX idx_currency_exchanges_created_at ON currency_exchanges (created_at)');
    await db.execute('CREATE INDEX idx_cash_transfers_number ON cash_transfers (transfer_number)');
    await db.execute('CREATE INDEX idx_cash_transfers_created_at ON cash_transfers (created_at)');

    // Audit Log
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id INTEGER,
        details TEXT,
        timestamp TEXT NOT NULL
      )
    ''');

    // Seed default data
    await _seedCurrencies(db);
    await _seedDefaultAccounts(db);
  }

  Future<void> _seedCurrencies(Database db) async {
    final now = DateTime.now().toIso8601String();
    final currencies = [
      {'code': 'YER', 'name_ar': 'ريال يمني', 'name_en': 'Yemeni Rial', 'symbol': 'ر.ي', 'exchange_rate': 1.0, 'is_default': 1, 'is_active': 1, 'created_at': now},
      {'code': 'SAR', 'name_ar': 'ريال سعودي', 'name_en': 'Saudi Riyal', 'symbol': 'ر.س', 'exchange_rate': 140.0, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'USD', 'name_ar': 'دولار أمريكي', 'name_en': 'US Dollar', 'symbol': r'$', 'exchange_rate': 530.0, 'is_default': 0, 'is_active': 1, 'created_at': now},
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
    // Removed: حساب الإيرادات (4000), حساب التكاليف (3000)
    // These duplicate the parent category name and are no longer needed
    // Kept: حساب المصاريف (5000), اجور النقل (5200) — required for expense/transport journal entries
    final templates = [
      ['حساب الأصول', 'Assets Account', '1000', 'ASSET'],
      ['حساب الصناديق والبنوك', 'Cash & Banks Account', '1100', 'ASSET'],
      ['حساب العملاء', 'Customers Account', '1200', 'ASSET'],
      ['حساب الخصوم', 'Liabilities Account', '2000', 'LIABILITY'],
      ['حساب الموردين', 'Suppliers Account', '2100', 'LIABILITY'],
      ['حساب المشتريات', 'Purchases Account', '3100', 'COST'],
      ['حساب المبيعات', 'Sales Account', '4100', 'REVENUE'],
      ['حساب المصاريف', 'Expenses Account', '5000', 'EXPENSE'],
      ['اجور النقل', 'Transport Charges', '5200', 'EXPENSE'],
      ['حساب الموظفين', 'Employees Account', '5100', 'EXPENSE'],
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
        final baseCode = int.parse(template[2]);
        final actualCode = (baseCode + codeOffset).toString();
        final account = makeAccount(
          template[0],
          template[1],
          actualCode,
          template[3],
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
    // Removed: حساب الإيرادات (4000), حساب التكاليف (3000)
    // Kept: حساب المصاريف (5000), اجور النقل (5200) — required for expense/transport journal entries
    final templates = [
      ['حساب الأصول', 'Assets Account', 1000, 'ASSET'],
      ['حساب الصناديق والبنوك', 'Cash & Banks Account', 1100, 'ASSET'],
      ['حساب العملاء', 'Customers Account', 1200, 'ASSET'],
      ['حساب الخصوم', 'Liabilities Account', 2000, 'LIABILITY'],
      ['حساب الموردين', 'Suppliers Account', 2100, 'LIABILITY'],
      ['حساب المشتريات', 'Purchases Account', 3100, 'COST'],
      ['حساب المبيعات', 'Sales Account', 4100, 'REVENUE'],
      ['حساب المصاريف', 'Expenses Account', 5000, 'EXPENSE'],
      ['اجور النقل', 'Transport Charges', 5200, 'EXPENSE'],
      ['حساب الموظفين', 'Employees Account', 5100, 'EXPENSE'],
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
    if (oldVersion < 9) {
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
          await db.delete('accounts', where: 'account_code = ?', whereArgs: [code]);
        } catch (_) {}
      }
    }

    if (oldVersion < 10) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_quotations_customer_id ON quotations (customer_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_quotations_status ON quotations (status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_quotation_items_quotation_id ON quotation_items (quotation_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON purchase_orders (supplier_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders (status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_order_items_po_id ON purchase_order_items (purchase_order_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_orders_customer_id ON sales_orders (customer_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_orders_status ON sales_orders (status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_order_items_so_id ON sales_order_items (sales_order_id)');
    }
    if (oldVersion < 11) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_shifts_cashier_id ON shifts (cashier_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_shifts_cash_box_id ON shifts (cash_box_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts (status)');
    }

    // ══════════════════════════════════════════════════════════════
    //  v12 Migration: shift columns on invoices, currency_exchanges, cash_transfers, updated exchange rates
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 12) {
      // Add shift-related columns to invoices
      try { await db.execute('ALTER TABLE invoices ADD COLUMN shift_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN cashier_name TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoices ADD COLUMN is_posted INTEGER NOT NULL DEFAULT 0'); } catch (_) {}

      // Create indexes for new invoice columns
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_shift_id ON invoices (shift_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_is_posted ON invoices (is_posted)'); } catch (_) {}

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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_currency_exchanges_number ON currency_exchanges (exchange_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_currency_exchanges_created_at ON currency_exchanges (created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_transfers_number ON cash_transfers (transfer_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_transfers_created_at ON cash_transfers (created_at)');

      // Update currency exchange rates: SAR = 140 YER, USD = 530 YER
      try {
        await db.update('currencies', {'exchange_rate': 140.0}, where: 'code = ?', whereArgs: ['SAR']);
        await db.update('currencies', {'exchange_rate': 530.0}, where: 'code = ?', whereArgs: ['USD']);
      } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v13 Migration: add currency column to cash_boxes, cashier_name to shifts
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 13) {
      // Add currency column to cash_boxes
      try { await db.execute("ALTER TABLE cash_boxes ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'"); } catch (_) {}

      // Add cashier_name column to shifts
      try { await db.execute("ALTER TABLE shifts ADD COLUMN cashier_name TEXT"); } catch (_) {}
    }
    if (oldVersion < 14) {
      // Add image_path column to products
      try { await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT'); } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v15 Migration: ensure currency column exists in cash_boxes,
    //  cashier_name in shifts (fixes missing columns from fresh installs)
    //
    //  NOTE: This migration duplicates v13 because some users who upgraded
    //  through v13 still had missing columns (fresh installs bypassed v13
    //  logic since _onCreate already included them). Keeping v15 ensures
    //  both upgrade paths and fresh-install fixes are covered.
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 15) {
      try { await db.execute("ALTER TABLE cash_boxes ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'"); } catch (_) {}
      try { await db.execute('ALTER TABLE shifts ADD COLUMN cashier_name TEXT'); } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v16 Migration: re-create expense and transport accounts that were
    //  incorrectly deleted by v9. These accounts are required for
    //  expense and transport charge journal entries.
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 16) {
      final now16 = DateTime.now().toIso8601String();
      final accountsToRestore = [
        {'name_ar': 'حساب المصاريف (ر.ي)', 'name_en': 'Expenses Account (YER)', 'account_code': '5000', 'account_type': 'EXPENSE', 'currency': 'YER', 'symbol': 'ر.ي'},
        {'name_ar': 'حساب المصاريف (ر.س)', 'name_en': 'Expenses Account (SAR)', 'account_code': '5001', 'account_type': 'EXPENSE', 'currency': 'SAR', 'symbol': 'ر.س'},
        {'name_ar': r'حساب المصاريف ($)', 'name_en': 'Expenses Account (USD)', 'account_code': '5002', 'account_type': 'EXPENSE', 'currency': 'USD', 'symbol': r'\$'},
        {'name_ar': 'اجور نقل (ر.ي)', 'name_en': 'Transport Charges (YER)', 'account_code': '5200', 'account_type': 'EXPENSE', 'currency': 'YER', 'symbol': 'ر.ي'},
        {'name_ar': 'اجور نقل (ر.س)', 'name_en': 'Transport Charges (SAR)', 'account_code': '5201', 'account_type': 'EXPENSE', 'currency': 'SAR', 'symbol': 'ر.س'},
        {'name_ar': r'اجور نقل ($)', 'name_en': 'Transport Charges (USD)', 'account_code': '5202', 'account_type': 'EXPENSE', 'currency': 'USD', 'symbol': r'\$'},
      ];
      for (final acct in accountsToRestore) {
        // Only insert if the account does not already exist
        final existing = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [acct['account_code'], acct['currency']], limit: 1);
        if (existing.isEmpty) {
          await db.insert('accounts', {
            'name_ar': acct['name_ar'],
            'name_en': acct['name_en'],
            'account_code': acct['account_code'],
            'account_type': acct['account_type'],
            'balance': 0.0,
            'currency': acct['currency'],
            'is_active': 1,
            'is_system': 1,
            'debt_ceiling': 0.0,
            'balance_type': 'credit',
            'created_at': now16,
            'updated_at': now16,
          });
        }
      }
    }

    if (oldVersion < 17) {
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
    // Check if product is referenced in invoice_items
    final refs = await db.query('invoice_items', where: 'product_id = ?', whereArgs: [id], limit: 1);
    if (refs.isNotEmpty) {
      // Soft-delete: product has history, cannot hard-delete
      return await db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
    }
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> decrementProductStock(int productId, double quantity) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
      [quantity, now, productId],
    );
  }

  /// Increment product stock (used for purchase invoices and sale return restocking).
  Future<void> incrementProductStock(int productId, double quantity) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
      [quantity, now, productId],
    );
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
    // Check if customer is referenced in invoices
    final refs = await db.query('invoices', where: 'customer_id = ?', whereArgs: [id], limit: 1);
    if (refs.isNotEmpty) {
      // Soft-delete not supported by schema — just prevent deletion
      return 0;
    }
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
    // Check if supplier is referenced in invoices
    final refs = await db.query('invoices', where: 'supplier_id = ?', whereArgs: [id], limit: 1);
    if (refs.isNotEmpty) {
      // Soft-delete not supported by schema — just prevent deletion
      return 0;
    }
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    final db = await database;
    final likeQuery = '%$query%';
    return await db.query('suppliers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: [likeQuery, likeQuery], orderBy: 'name ASC');
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
  /// [deferPosting] - if true, skip journal entries (for POS deferred posting until shift close).
  Future<void> saveInvoiceWithJournalEntries(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items, {
    required String invoiceType,
    required String paymentMechanism,
    required bool isReturn,
    int? cashBoxId,
    double transportCharges = 0.0,
    bool deferPosting = false,
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

      // ── Stock management ──
      // Sale/POS: decrement stock; Purchase: increment stock; Returns do the opposite
      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        if (productId == null) continue;

        if (invoiceType == 'sale' || invoiceType == 'pos') {
          if (!isReturn) {
            // Sale: stock leaves warehouse
            await txn.rawUpdate(
              'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
              [quantity, now, productId],
            );
          } else {
            // Sale return: stock returns to warehouse
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
              [quantity, now, productId],
            );
          }
        } else if (invoiceType == 'purchase') {
          if (!isReturn) {
            // Purchase: stock enters warehouse
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
              [quantity, now, productId],
            );
          } else {
            // Purchase return: stock leaves warehouse
            await txn.rawUpdate(
              'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
              [quantity, now, productId],
            );
          }
        }
      }

      // ── Deferred posting: skip journal entries for POS invoices ──
      // Journal entries will be created by postShiftInvoices() when the shift is closed.
      // This prevents double-posting (once at sale time and again at shift close).
      if (deferPosting) {
        return; // Stock already updated above; journal entries deferred to shift close.
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

      if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
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
          'description': '${(invoiceMap['type'] == 'sale' || invoiceMap['type'] == 'pos') ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - ${invoiceMap['id']}',
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
          'description': '${(invoiceMap['type'] == 'sale' || invoiceMap['type'] == 'pos') ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - ${invoiceMap['id']}',
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
        final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn);
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

  /// Soft-delete an invoice by setting status to 'cancelled'.
  /// Does NOT reverse journal entries — use [cancelInvoice] for full reversal.
  Future<int> deleteInvoice(String id) async {
    final db = await database;
    return await db.update('invoices', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [id]);
  }

  /// Cancel an invoice: soft-delete + reversal journal entries + balance reversals + stock restore.
  Future<void> cancelInvoice(String id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Fetch invoice
    final invoiceRows = await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    if (invoiceRows.isEmpty) return;
    final invoice = invoiceRows.first;

    // Already cancelled — nothing to do
    if ((invoice['status'] as String?) == 'cancelled') return;

    final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
    final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
    final invoiceType = (invoice['type'] as String?) ?? 'sale';
    final isReturn = (invoice['is_return'] as int?) == 1;
    final paymentMechanism = (invoice['payment_mechanism'] as String?) ?? 'cash';
    final cashBoxId = invoice['cash_box_id'] as int?;
    final transportCharges = (invoice['transport_charges'] as num?)?.toDouble() ?? 0.0;

    // Fetch items for stock reversal
    final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);

    await db.transaction((txn) async {
      // 1. Set status to cancelled
      await txn.update('invoices', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [id]);

      // 2. Create reversal journal entries
      final journalId = DateTime.now().millisecondsSinceEpoch;
      final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

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

      // Determine original debit/credit accounts (same logic as saveInvoiceWithJournalEntries)
      int? originalDebitAccountId;
      int? originalCreditAccountId;

      if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
        if (isReturn) {
          originalDebitAccountId = salesAccountId;
          originalCreditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
        } else {
          originalDebitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          originalCreditAccountId = salesAccountId;
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        if (isReturn) {
          originalDebitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          originalCreditAccountId = purchasesAccountId;
        } else {
          originalDebitAccountId = purchasesAccountId;
          originalCreditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
        }
      }

      // Reversal: swap debit/credit
      if (originalCreditAccountId != null && total > 0) {
        await txn.insert('transactions', {
          'account_id': originalCreditAccountId,
          'journal_id': journalId,
          'debit': total,
          'credit': 0.0,
          'description': 'إلغاء فاتورة - $id',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [total, now, originalCreditAccountId]);
      }
      if (originalDebitAccountId != null && total > 0) {
        await txn.insert('transactions', {
          'account_id': originalDebitAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': total,
          'description': 'إلغاء فاتورة - $id',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [total, now, originalDebitAccountId]);
      }

      // 3. Reverse transport charge journal entries
      if (transportCharges > 0) {
        final transportAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(5200 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final transportAccountId = transportAccount.isNotEmpty ? transportAccount.first['id'] as int : null;

        if (invoiceType == 'sale' || invoiceType == 'sale_return') {
          // Original: Debit customer/cash, Credit transport expense
          // Reversal: Debit transport expense, Credit customer/cash
          final reversalDebitId = transportAccountId;
          final reversalCreditId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;

          if (reversalDebitId != null) {
            await txn.insert('transactions', {
              'account_id': reversalDebitId,
              'journal_id': journalId,
              'debit': transportCharges,
              'credit': 0.0,
              'description': 'إلغاء اجور نقل - $id',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [transportCharges, now, reversalDebitId]);
          }
          if (reversalCreditId != null) {
            await txn.insert('transactions', {
              'account_id': reversalCreditId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': transportCharges,
              'description': 'إلغاء اجور نقل - $id',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, reversalCreditId]);
          }
        } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
          // Original: Debit transport expense, Credit cash/supplier
          // Reversal: Debit cash/supplier, Credit transport expense
          final reversalDebitId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          final reversalCreditId = transportAccountId;

          if (reversalDebitId != null) {
            await txn.insert('transactions', {
              'account_id': reversalDebitId,
              'journal_id': journalId,
              'debit': transportCharges,
              'credit': 0.0,
              'description': 'إلغاء اجور نقل - $id',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [transportCharges, now, reversalDebitId]);
          }
          if (reversalCreditId != null) {
            await txn.insert('transactions', {
              'account_id': reversalCreditId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': transportCharges,
              'description': 'إلغاء اجور نقل - $id',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, reversalCreditId]);
          }
        }
      }

      // 4. Reverse customer/supplier balance
      if (invoice['customer_id'] != null) {
        final wasDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
        final totalWithTransport = total + (transportCharges > 0 && paymentMechanism == 'credit' && (invoiceType == 'sale' || invoiceType == 'sale_return') ? transportCharges : 0);
        if (wasDebit) {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['customer_id']]);
        } else {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['customer_id']]);
        }
      }

      if (invoice['supplier_id'] != null) {
        final wasCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
        final totalWithTransport = total + (transportCharges > 0 && paymentMechanism == 'credit' && (invoiceType == 'purchase' || invoiceType == 'purchase_return') ? transportCharges : 0);
        if (wasCreditToSupplier) {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['supplier_id']]);
        } else {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['supplier_id']]);
        }
      }

      // 5. Reverse cash box balance
      if (cashBoxId != null) {
        final wasCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn) || (invoiceType == 'pos' && !isReturn);
        if (wasCashIn) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [total, now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [total, now, cashBoxId]);
        }
        // Reverse transport charge cash box effect
        if (transportCharges > 0) {
          if (invoiceType == 'sale' || invoiceType == 'sale_return') {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, cashBoxId]);
          } else {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [transportCharges, now, cashBoxId]);
          }
        }
      }

      // 6. Restore product stock
      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        if (productId == null) continue;

        if (invoiceType == 'sale' || invoiceType == 'pos') {
          if (!isReturn) {
            // Was decremented, now restore
            await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
          } else {
            // Was incremented (return), now decrement
            await txn.rawUpdate('UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?', [quantity, now, productId]);
          }
        } else if (invoiceType == 'purchase') {
          if (!isReturn) {
            // Was incremented, now decrement
            await txn.rawUpdate('UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?', [quantity, now, productId]);
          } else {
            // Was decremented (return), now restore
            await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
          }
        }
      }
    });
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

  /// Save expense with journal entry.
  /// Supports operation_type: 'صرف' (disburse - debit expense, credit cash) or 'قبض' (receive - debit cash, credit expense).
  Future<void> saveExpenseWithJournalEntry(Map<String, dynamic> expenseMap) async {
    final db = await database;
    final amountBase = (expenseMap['amount_base'] as num?)?.toDouble() ?? 0.0;
    final expenseCurrency = (expenseMap['currency'] as String?) ?? 'YER';
    final operationType = (expenseMap['operation_type'] as String?) ?? 'صرف';
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
      int? expenseAccId = expenseAccountId;

      if (expenseAccId == null) {
        final expenseAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(5000 + codeOffset).toString(), expenseCurrency], limit: 1);
        expenseAccId = expenseAccount.isNotEmpty ? expenseAccount.first['id'] as int : null;
      }

      // Get cash/bank account (code 1100+offset) or use cash box linked account
      int? cashAccountId;
      final cashBoxId = expenseMap['cash_box_id'] as int?;
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final linkedAccountId = cashBox.first['linked_account_id'] as int?;
          if (linkedAccountId != null) {
            cashAccountId = linkedAccountId;
          }
        }
      }
      if (cashAccountId == null) {
        final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), expenseCurrency], limit: 1);
        cashAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
      }

      final title = expenseMap['title'] as String? ?? 'مصروف';
      final isSarf = operationType == 'صرف';

      if (isSarf) {
        // صرف (disburse): Debit expense account, Credit cash/bank
        if (expenseAccId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': expenseAccId,
            'journal_id': journalId,
            'debit': amountBase,
            'credit': 0.0,
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [amountBase, now, expenseAccId]);
        }
        if (cashAccountId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': cashAccountId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': amountBase,
            'description': 'مصروف: $title',
            'date': now,
            'created_at': now,
          });
          await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [amountBase, now, cashAccountId]);
        }
      } else {
        // قبض (receive): Debit cash/bank, Credit expense account
        if (cashAccountId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': cashAccountId,
            'journal_id': journalId,
            'debit': amountBase,
            'credit': 0.0,
            'description': 'قبض: $title',
            'date': now,
            'created_at': now,
          });
          await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [amountBase, now, cashAccountId]);
        }
        if (expenseAccId != null && amountBase > 0) {
          await txn.insert('transactions', {
            'account_id': expenseAccId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': amountBase,
            'description': 'قبض: $title',
            'date': now,
            'created_at': now,
          });
          await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [amountBase, now, expenseAccId]);
        }
      }

      // Update cash box balance
      if (cashBoxId != null && amountBase > 0) {
        if (isSarf) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [amountBase, now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [amountBase, now, cashBoxId]);
        }
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

  /// Get expense accounts filtered by currency
  Future<List<Map<String, dynamic>>> getExpenseAccountsByCurrency(String currency) async {
    final db = await database;
    return await db.query('accounts', where: 'is_active = ? AND account_type = ? AND currency = ?', whereArgs: [1, 'EXPENSE', currency], orderBy: 'account_code ASC');
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

  Future<int> updateCategory(int id, Map<String, dynamic> categoryMap) async {
    final db = await database;
    return await db.update('categories', categoryMap, where: 'id = ?', whereArgs: [id]);
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
    if (account.isEmpty) return 0;
    if ((account.first['is_system'] as int?) == 1) {
      return -1; // Cannot delete system account
    }
    // Check for child accounts
    final children = await db.query('accounts', where: 'parent_id = ?', whereArgs: [id], limit: 1);
    if (children.isNotEmpty) {
      return -2; // Cannot delete account with child accounts
    }
    // Check for transactions referencing this account
    final transactions = await db.query('transactions', where: 'account_id = ?', whereArgs: [id], limit: 1);
    if (transactions.isNotEmpty) {
      return -3; // Cannot delete account with transactions
    }
    // Remove linked_cash_box_id references
    await db.rawUpdate('UPDATE cash_boxes SET linked_account_id = NULL WHERE linked_account_id = ?', [id]);
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  /// Get the next available account code for a given account type.
  /// Uses 4-digit numeric codes where the first digit is the type prefix.
  /// Steps by 10 to leave room for sub-accounts.
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
      'SELECT COALESCE(MAX(CAST(account_code AS INTEGER)), 0) AS max_code FROM accounts WHERE account_code LIKE ? AND account_type = ?',
      ['$prefix%', accountType],
    );
    final maxCode = (result.first['max_code'] as num?)?.toInt() ?? 0;
    // If no existing codes, start at prefix*1000 + 10 (e.g. 1010 for ASSET)
    final nextCode = maxCode == 0 ? (int.parse(prefix) * 1000 + 10) : maxCode + 10;
    return nextCode.toString();
  }

  /// Reconcile an account's balance column with the actual computed balance from transactions.
  /// Computes SUM(debit) - SUM(credit) and updates the `balance` column.
  Future<void> reconcileAccountBalance(int accountId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0.0) AS computed_balance FROM transactions WHERE account_id = ?',
      [accountId],
    );
    final computedBalance = (result.first['computed_balance'] as num?)?.toDouble() ?? 0.0;
    await db.update('accounts', {'balance': computedBalance, 'updated_at': now}, where: 'id = ?', whereArgs: [accountId]);
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

  /// Alias for getAllEmployees - used by some screens
  Future<List<Map<String, dynamic>>> getEmployees() async {
    return getAllEmployees();
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
  //  Audit log methods
  // ══════════════════════════════════════════════════════════════

  /// Log an audit event for tracking data changes.
  Future<void> logAuditEvent(String action, String tableName, int? recordId, {String? details}) async {
    final db = await database;
    await db.insert('audit_log', {
      'action': action,
      'table_name': tableName,
      'record_id': recordId,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ══════════════════════════════════════════════════════════════
  //  Dashboard query methods
  // ══════════════════════════════════════════════════════════════

  Future<double> getTotalSalesForDate(DateTime date) async {
    final db = await database;
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) = ?", [dateStr]);
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
    final result = await db.rawQuery("SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?", [monthStart]);
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
      WHERE type IN ('sale', 'sale_return', 'pos') AND is_return = 0 AND date(created_at) >= ?
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

  // ══════════════════════════════════════════════════════════════
  //  Quotation CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertQuotationWithItems(Map<String, dynamic> quotationMap, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('quotations', quotationMap);
      for (final item in items) {
        await txn.insert('quotation_items', item);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllQuotations({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT q.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM quotations q
      LEFT JOIN customers c ON q.customer_id = c.id
      ORDER BY q.$orderBy
    ''');
  }

  Future<List<Map<String, dynamic>>> getQuotationsByStatus(String status) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT q.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM quotations q
      LEFT JOIN customers c ON q.customer_id = c.id
      WHERE q.status = ?
      ORDER BY q.created_at DESC
    ''', [status]);
  }

  Future<Map<String, dynamic>?> getQuotationById(String id) async {
    final db = await database;
    final results = await db.query('quotations', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getQuotationItems(String quotationId) async {
    final db = await database;
    return await db.query('quotation_items', where: 'quotation_id = ?', whereArgs: [quotationId]);
  }

  Future<int> updateQuotation(String id, Map<String, dynamic> quotationMap) async {
    final db = await database;
    return await db.update('quotations', quotationMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteQuotation(String id) async {
    final db = await database;
    await db.delete('quotation_items', where: 'quotation_id = ?', whereArgs: [id]);
    return await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextQuotationNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'QT-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(quotation_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM quotations WHERE quotation_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Purchase Order CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertPurchaseOrderWithItems(Map<String, dynamic> poMap, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('purchase_orders', poMap);
      for (final item in items) {
        await txn.insert('purchase_order_items', item);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllPurchaseOrders({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT po.*, COALESCE(s.name, 'بدون مورد') AS supplier_name
      FROM purchase_orders po
      LEFT JOIN suppliers s ON po.supplier_id = s.id
      ORDER BY po.$orderBy
    ''');
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrdersByStatus(String status) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT po.*, COALESCE(s.name, 'بدون مورد') AS supplier_name
      FROM purchase_orders po
      LEFT JOIN suppliers s ON po.supplier_id = s.id
      WHERE po.status = ?
      ORDER BY po.created_at DESC
    ''', [status]);
  }

  Future<Map<String, dynamic>?> getPurchaseOrderById(String id) async {
    final db = await database;
    final results = await db.query('purchase_orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrderItems(String poId) async {
    final db = await database;
    return await db.query('purchase_order_items', where: 'purchase_order_id = ?', whereArgs: [poId]);
  }

  Future<int> updatePurchaseOrder(String id, Map<String, dynamic> poMap) async {
    final db = await database;
    return await db.update('purchase_orders', poMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletePurchaseOrder(String id) async {
    final db = await database;
    await db.delete('purchase_order_items', where: 'purchase_order_id = ?', whereArgs: [id]);
    return await db.delete('purchase_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextPurchaseOrderNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(order_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM purchase_orders WHERE order_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Sales Order CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<void> insertSalesOrderWithItems(Map<String, dynamic> soMap, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('sales_orders', soMap);
      for (final item in items) {
        await txn.insert('sales_order_items', item);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllSalesOrders({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT so.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM sales_orders so
      LEFT JOIN customers c ON so.customer_id = c.id
      ORDER BY so.$orderBy
    ''');
  }

  Future<List<Map<String, dynamic>>> getSalesOrdersByStatus(String status) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT so.*, COALESCE(c.name, 'بدون عميل') AS customer_name
      FROM sales_orders so
      LEFT JOIN customers c ON so.customer_id = c.id
      WHERE so.status = ?
      ORDER BY so.created_at DESC
    ''', [status]);
  }

  Future<Map<String, dynamic>?> getSalesOrderById(String id) async {
    final db = await database;
    final results = await db.query('sales_orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getSalesOrderItems(String soId) async {
    final db = await database;
    return await db.query('sales_order_items', where: 'sales_order_id = ?', whereArgs: [soId]);
  }

  Future<int> updateSalesOrder(String id, Map<String, dynamic> soMap) async {
    final db = await database;
    return await db.update('sales_orders', soMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSalesOrder(String id) async {
    final db = await database;
    await db.delete('sales_order_items', where: 'sales_order_id = ?', whereArgs: [id]);
    return await db.delete('sales_orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextSalesOrderNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'SO-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(order_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM sales_orders WHERE order_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  Shift (وردية) CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> openShift(Map<String, dynamic> shiftMap) async {
    final db = await database;
    return await db.insert('shifts', shiftMap);
  }

  Future<Map<String, dynamic>?> getActiveShift(int cashBoxId) async {
    final db = await database;
    final results = await db.query('shifts', where: 'cash_box_id = ? AND status = ?', whereArgs: [cashBoxId, 'open'], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getActiveShiftForCashier(int? cashierId) async {
    final db = await database;
    if (cashierId == null) return null;
    final results = await db.query('shifts', where: 'cashier_id = ? AND status = ?', whereArgs: [cashierId, 'open'], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> closeShift(int shiftId, Map<String, dynamic> closeData) async {
    final db = await database;
    return await db.update('shifts', closeData, where: 'id = ?', whereArgs: [shiftId]);
  }

  Future<List<Map<String, dynamic>>> getAllShifts({String orderBy = 'opened_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.*, cb.name AS cash_box_name
      FROM shifts s
      LEFT JOIN cash_boxes cb ON s.cash_box_id = cb.id
      ORDER BY s.$orderBy
    ''');
  }

  Future<String> getNextShiftNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'SH-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(shift_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM shifts WHERE shift_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  Future<void> updateShiftTotals(int shiftId, double saleAmount, double returnAmount, double discountAmount) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE shifts SET 
        total_sales = total_sales + ?,
        total_returns = total_returns + ?,
        total_discounts = total_discounts + ?,
        transaction_count = transaction_count + 1,
        expected_amount = opening_amount + total_sales + ? - total_returns - total_discounts - ?,
        updated_at = ?
      WHERE id = ?
    ''', [saleAmount, returnAmount, discountAmount, saleAmount, discountAmount, DateTime.now().toIso8601String(), shiftId]);
  }

  // ══════════════════════════════════════════════════════════════
  //  v12: Currency Exchange (صرافة العملات) CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// إدراج عملية صرافة عملات مع القيود المحاسبية
  /// Inserts a currency exchange record and posts journal entries.
  ///
  /// القيود المحاسبية:
  /// - مدين: حساب الصناديق والبنوك للعملة المستلمة (to_currency) بالمبلغ المستلم
  /// - دائن: حساب الصناديق والبنوك للعملة المرسلة (from_currency) بالمبلغ المرسل
  /// - إذا كان هناك أرباح صرافة: دائن حساب أرباح الصرافة
  /// - إذا كان هناك خسائر صرافة: مدين حساب خسائر الصرافة
  Future<int> insertCurrencyExchange(Map<String, dynamic> exchangeMap) async {
    final db = await database;
    final fromCurrency = (exchangeMap['from_currency'] as String?) ?? 'YER';
    final toCurrency = (exchangeMap['to_currency'] as String?) ?? 'YER';
    final fromAmount = (exchangeMap['from_amount'] as num?)?.toDouble() ?? 0.0;
    final toAmount = (exchangeMap['to_amount'] as num?)?.toDouble() ?? 0.0;
    final gainLoss = (exchangeMap['gain_loss'] as num?)?.toDouble() ?? 0.0;
    final gainLossType = (exchangeMap['gain_loss_type'] as String?) ?? '';
    final fromCashBoxId = (exchangeMap['from_cash_box_id'] as num?)?.toInt() ?? 0;
    final toCashBoxId = (exchangeMap['to_cash_box_id'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toIso8601String();

    late int exchangeId;
    await db.transaction((txn) async {
      // إدراج سجل الصرافة
      exchangeId = await txn.insert('currency_exchanges', exchangeMap);

      // القيود المحاسبية
      final journalId = DateTime.now().millisecondsSinceEpoch;

      // حساب الصناديق والبنوك للعملة المستلمة (مدين)
      final toCodeOffset = toCurrency == 'SAR' ? 1 : (toCurrency == 'USD' ? 2 : 0);
      final toCashBanksAccount = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1100 + toCodeOffset).toString(), toCurrency],
        limit: 1,
      );
      final toCashBanksAccountId = toCashBanksAccount.isNotEmpty ? toCashBanksAccount.first['id'] as int : null;

      // حساب الصناديق والبنوك للعملة المرسلة (دائن)
      final fromCodeOffset = fromCurrency == 'SAR' ? 1 : (fromCurrency == 'USD' ? 2 : 0);
      final fromCashBanksAccount = await txn.query(
        'accounts',
        where: 'account_code = ? AND currency = ?',
        whereArgs: [(1100 + fromCodeOffset).toString(), fromCurrency],
        limit: 1,
      );
      final fromCashBanksAccountId = fromCashBanksAccount.isNotEmpty ? fromCashBanksAccount.first['id'] as int : null;

      // مدين: حساب الصناديق والبنوك للعملة المستلمة
      if (toCashBanksAccountId != null && toAmount > 0) {
        await txn.insert('transactions', {
          'account_id': toCashBanksAccountId,
          'journal_id': journalId,
          'debit': toAmount,
          'credit': 0.0,
          'description': 'صرافة: استلام $toCurrency - ${exchangeMap['exchange_number']}',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [toAmount, now, toCashBanksAccountId]);
      }

      // دائن: حساب الصناديق والبنوك للعملة المرسلة
      if (fromCashBanksAccountId != null && fromAmount > 0) {
        await txn.insert('transactions', {
          'account_id': fromCashBanksAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': fromAmount,
          'description': 'صرافة: صرف $fromCurrency - ${exchangeMap['exchange_number']}',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [fromAmount, now, fromCashBanksAccountId]);
      }

      // معالجة أرباح/خسائر الصرافة
      if (gainLoss > 0) {
        if (gainLossType == 'gain') {
          // أرباح صرافة: دائن حساب أرباح الصرافة
          // استخدام حساب إيراد بالعملة الأساسية (YER)
          final gainCodeOffset = 0; // أرباح الصرافة تُسجل بالعملة الأساسية
          final gainAccount = await txn.query(
            'accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(4100 + gainCodeOffset).toString(), 'YER'],
            limit: 1,
          );
          final gainAccountId = gainAccount.isNotEmpty ? gainAccount.first['id'] as int : null;

          if (gainAccountId != null) {
            await txn.insert('transactions', {
              'account_id': gainAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': gainLoss,
              'description': 'أرباح صرافة - ${exchangeMap['exchange_number']}',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [gainLoss, now, gainAccountId]);
          }
        } else if (gainLossType == 'loss') {
          // خسائر صرافة: مدين حساب خسائر الصرافة
          final lossCodeOffset = 0; // خسائر الصرافة تُسجل بالعملة الأساسية (YER)
          final lossAccount = await txn.query(
            'accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [(5100 + lossCodeOffset).toString(), 'YER'],
            limit: 1,
          );
          final lossAccountId = lossAccount.isNotEmpty ? lossAccount.first['id'] as int : null;

          if (lossAccountId != null) {
            await txn.insert('transactions', {
              'account_id': lossAccountId,
              'journal_id': journalId,
              'debit': gainLoss,
              'credit': 0.0,
              'description': 'خسائر صرافة - ${exchangeMap['exchange_number']}',
              'date': now,
              'created_at': now,
            });
            await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [gainLoss, now, lossAccountId]);
          }
        }
      }

      // تحديث أرصدة الصناديق
      // خصم المبلغ من صندوق المصدر
      await txn.rawUpdate(
        'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
        [fromAmount, now, fromCashBoxId],
      );
      // إضافة المبلغ إلى صندوق المستقبل
      await txn.rawUpdate(
        'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
        [toAmount, now, toCashBoxId],
      );
    });

    return exchangeId;
  }

  /// جلب جميع عمليات الصرافة
  Future<List<Map<String, dynamic>>> getAllCurrencyExchanges({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ce.*,
        from_cb.name AS from_cash_box_name,
        to_cb.name AS to_cash_box_name
      FROM currency_exchanges ce
      LEFT JOIN cash_boxes from_cb ON ce.from_cash_box_id = from_cb.id
      LEFT JOIN cash_boxes to_cb ON ce.to_cash_box_id = to_cb.id
      ORDER BY ce.$orderBy
    ''');
  }

  /// جلب الرقم التالي لعملية الصرافة
  Future<String> getNextExchangeNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'CE-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(exchange_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM currency_exchanges WHERE exchange_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  v12: Cash Transfer (تحويل بين الصناديق) CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// إدراج عملية تحويل بين الصناديق مع القيود المحاسبية
  /// Inserts a cash transfer record and posts journal entries.
  ///
  /// القيود المحاسبية:
  /// - مدين: حساب الصناديق والبنوك المرتبط بصندوق الوجهة
  /// - دائن: حساب الصناديق والبنوك المرتبط بصندوق المصدر
  Future<int> insertCashTransfer(Map<String, dynamic> transferMap) async {
    final db = await database;
    final fromCashBoxId = (transferMap['from_cash_box_id'] as num?)?.toInt() ?? 0;
    final toCashBoxId = (transferMap['to_cash_box_id'] as num?)?.toInt() ?? 0;
    final amount = (transferMap['amount'] as num?)?.toDouble() ?? 0.0;
    final transferCurrency = (transferMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    late int transferId;
    await db.transaction((txn) async {
      // إدراج سجل التحويل
      transferId = await txn.insert('cash_transfers', transferMap);

      // القيود المحاسبية
      final journalId = DateTime.now().millisecondsSinceEpoch;

      // الحصول على حساب الصندوق المصدر (المرتبط أو الافتراضي)
      int? fromAccountId;
      final fromCashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [fromCashBoxId], limit: 1);
      if (fromCashBox.isNotEmpty) {
        final linkedId = fromCashBox.first['linked_account_id'] as int?;
        if (linkedId != null) {
          fromAccountId = linkedId;
        }
      }
      if (fromAccountId == null) {
        final codeOffset = transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final fromCashBanksAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), transferCurrency],
          limit: 1,
        );
        fromAccountId = fromCashBanksAccount.isNotEmpty ? fromCashBanksAccount.first['id'] as int : null;
      }

      // الحصول على حساب الصندوق الوجهة (المرتبط أو الافتراضي)
      int? toAccountId;
      final toCashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [toCashBoxId], limit: 1);
      if (toCashBox.isNotEmpty) {
        final linkedId = toCashBox.first['linked_account_id'] as int?;
        if (linkedId != null) {
          toAccountId = linkedId;
        }
      }
      if (toAccountId == null) {
        final codeOffset = transferCurrency == 'SAR' ? 1 : (transferCurrency == 'USD' ? 2 : 0);
        final toCashBanksAccount = await txn.query(
          'accounts',
          where: 'account_code = ? AND currency = ?',
          whereArgs: [(1100 + codeOffset).toString(), transferCurrency],
          limit: 1,
        );
        toAccountId = toCashBanksAccount.isNotEmpty ? toCashBanksAccount.first['id'] as int : null;
      }

      // مدين: حساب الصناديق والبنوك للوجهة
      if (toAccountId != null && amount > 0) {
        await txn.insert('transactions', {
          'account_id': toAccountId,
          'journal_id': journalId,
          'debit': amount,
          'credit': 0.0,
          'description': 'تحويل: استلام من صندوق آخر - ${transferMap['transfer_number']}',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [amount, now, toAccountId]);
      }

      // دائن: حساب الصناديق والبنوك للمصدر
      if (fromAccountId != null && amount > 0) {
        await txn.insert('transactions', {
          'account_id': fromAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': amount,
          'description': 'تحويل: صرف إلى صندوق آخر - ${transferMap['transfer_number']}',
          'date': now,
          'created_at': now,
        });
        await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [amount, now, fromAccountId]);
      }

      // تحديث أرصدة الصناديق
      // خصم المبلغ من صندوق المصدر
      await txn.rawUpdate(
        'UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?',
        [amount, now, fromCashBoxId],
      );
      // إضافة المبلغ إلى صندوق الوجهة
      await txn.rawUpdate(
        'UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?',
        [amount, now, toCashBoxId],
      );
    });

    return transferId;
  }

  /// جلب جميع عمليات التحويل بين الصناديق
  Future<List<Map<String, dynamic>>> getAllCashTransfers({String orderBy = 'created_at DESC'}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ct.*,
        from_cb.name AS from_cash_box_name,
        to_cb.name AS to_cash_box_name
      FROM cash_transfers ct
      LEFT JOIN cash_boxes from_cb ON ct.from_cash_box_id = from_cb.id
      LEFT JOIN cash_boxes to_cb ON ct.to_cash_box_id = to_cb.id
      ORDER BY ct.$orderBy
    ''');
  }

  /// جلب الرقم التالي لعملية التحويل
  Future<String> getNextTransferNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'TR-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(MAX(CAST(SUBSTR(transfer_number, 10) AS INTEGER)), 0) + 1 AS next_num FROM cash_transfers WHERE transfer_number LIKE ?",
      ['$prefix%'],
    );
    final nextNum = (result.first['next_num'] as num?)?.toInt() ?? 1;
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  //  v12: Shift Invoice & Posting methods
  // ══════════════════════════════════════════════════════════════

  /// جلب جميع فواتير الوردية المحددة
  /// Get all invoices for a specific shift.
  Future<List<Map<String, dynamic>>> getShiftInvoices(int shiftId) async {
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
      WHERE i.shift_id = ?
      ORDER BY i.created_at DESC
    ''', [shiftId]);
  }

  /// ترحيل جميع الفواتير المعلقة في وردية محددة
  /// Post all pending invoices in a shift by creating journal entries.
  ///
  /// عند إقفال الوردية، يتم إنشاء القيود المحاسبية لجميع الفواتير
  /// التي لم يتم ترحيلها (is_posted = 0) وتحديث حالتها إلى مرحلة (is_posted = 1).
  Future<int> postShiftInvoices(int shiftId) async {
    final db = await database;
    int postedCount = 0;
    final now = DateTime.now().toIso8601String();

    // جلب جميع الفواتير المعلقة في الوردية
    final pendingInvoices = await db.query(
      'invoices',
      where: 'shift_id = ? AND is_posted = ?',
      whereArgs: [shiftId, 0],
    );

    for (final invoice in pendingInvoices) {
      final invoiceId = invoice['id'] as String;
      final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
      final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
      final invoiceType = (invoice['type'] as String?) ?? 'sale';
      final isReturn = (invoice['is_return'] as int?) == 1;
      final paymentMechanism = (invoice['payment_mechanism'] as String?) ?? 'cash';
      final cashBoxId = invoice['cash_box_id'] as int?;
      final transportCharges = (invoice['transport_charges'] as num?)?.toDouble() ?? 0.0;

      await db.transaction((txn) async {
        final journalId = DateTime.now().millisecondsSinceEpoch;

        // تحديد إزاحة كود الحساب حسب العملة
        final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

        // جلب معرفات الحسابات
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

        int? debitAccountId;
        int? creditAccountId;

        if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
          if (isReturn) {
            debitAccountId = salesAccountId;
            creditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          } else {
            debitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
            creditAccountId = salesAccountId;
          }
        } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
          if (isReturn) {
            debitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
            creditAccountId = purchasesAccountId;
          } else {
            debitAccountId = purchasesAccountId;
            creditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          }
        }

        // إنشاء القيود المحاسبية
        if (debitAccountId != null && total > 0) {
          await txn.insert('transactions', {
            'account_id': debitAccountId,
            'journal_id': journalId,
            'debit': total,
            'credit': 0.0,
            'description': '${(invoiceType == 'sale' || invoiceType == 'pos') ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await txn.rawUpdate('UPDATE accounts SET balance = balance + ?, updated_at = ? WHERE id = ?', [total, now, debitAccountId]);
        }

        if (creditAccountId != null && total > 0) {
          await txn.insert('transactions', {
            'account_id': creditAccountId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': total,
            'description': '${(invoiceType == 'sale' || invoiceType == 'pos') ? 'فاتورة مبيعات' : 'فاتورة مشتريات'}${isReturn ? ' - مرتجع' : ''} - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [total, now, creditAccountId]);
        }

        // ── قيود أجور النقل ──
        if (transportCharges > 0) {
          final transportAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(5200 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final transportAccountId = transportAccount.isNotEmpty ? transportAccount.first['id'] as int : null;

          if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
            final transportDebitId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
            final transportCreditId = transportAccountId;

            if (transportDebitId != null) {
              await txn.insert('transactions', {
                'account_id': transportDebitId,
                'journal_id': journalId,
                'debit': transportCharges,
                'credit': 0.0,
                'description': 'اجور نقل - $invoiceId',
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
                'description': 'اجور نقل - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, transportCreditId]);
            }
          } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
            final transportDebitId = transportAccountId;
            final transportCreditId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;

            if (transportDebitId != null) {
              await txn.insert('transactions', {
                'account_id': transportDebitId,
                'journal_id': journalId,
                'debit': transportCharges,
                'credit': 0.0,
                'description': 'اجور نقل - $invoiceId',
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
                'description': 'اجور نقل - $invoiceId',
                'date': now,
                'created_at': now,
              });
              await txn.rawUpdate('UPDATE accounts SET balance = balance - ?, updated_at = ? WHERE id = ?', [transportCharges, now, transportCreditId]);
            }
          }
        }

        // تحديث رصيد العميل/المورد
        if (invoice['customer_id'] != null) {
          final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'pos' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
          final totalWithTransport = total + (transportCharges > 0 && paymentMechanism == 'credit' && (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') ? transportCharges : 0);
          if (isDebit) {
            await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['customer_id']]);
          } else {
            await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['customer_id']]);
          }
        }

        if (invoice['supplier_id'] != null) {
          final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
          final totalWithTransport = total + (transportCharges > 0 && paymentMechanism == 'credit' && (invoiceType == 'purchase' || invoiceType == 'purchase_return') ? transportCharges : 0);
          if (isCreditToSupplier) {
            await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['supplier_id']]);
          } else {
            await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalWithTransport, now, invoice['supplier_id']]);
          }
        }

        // تحديث رصيد الصندوق
        if (cashBoxId != null) {
          final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn) || (invoiceType == 'pos' && !isReturn);
          if (isCashIn) {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [total, now, cashBoxId]);
          } else {
            await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [total, now, cashBoxId]);
          }
        }

        // تحديث حالة الفاتورة إلى مرحلة
        await txn.update('invoices', {'is_posted': 1}, where: 'id = ?', whereArgs: [invoiceId]);
      });

      postedCount++;
    }

    return postedCount;
  }

  // ══════════════════════════════════════════════════════════════
  //  v12: Additional lookup methods
  // ══════════════════════════════════════════════════════════════

  /// جلب الصناديق حسب العملة
  /// Get cash boxes filtered by currency (via linked account currency).
  Future<List<Map<String, dynamic>>> getCashBoxesByCurrency(String currency) async {
    final db = await database;
    // الصناديق المرتبطة بحساب بعملة محددة
    return await db.rawQuery('''
      SELECT cb.* FROM cash_boxes cb
      LEFT JOIN accounts a ON cb.linked_account_id = a.id
      WHERE cb.is_active = 1 AND (
        (a.currency = ?) OR (cb.linked_account_id IS NULL)
      )
      ORDER BY cb.type ASC, cb.name ASC
    ''', [currency]);
  }

  /// جلب حساب بكود وعملة محددة
  /// Get account by code and currency.
  Future<Map<String, dynamic>?> getAccountByCodeAndCurrency(String code, String currency) async {
    final db = await database;
    final results = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [code, currency], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  /// Count POS invoices for a given date prefix (e.g. '2026-03-04')
  /// Used to avoid invoice-ID collisions after app restart.
  Future<int> getTodayPosInvoiceCount(String datePrefix) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE id LIKE ?",
      ['POS-$datePrefix%'],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

}
