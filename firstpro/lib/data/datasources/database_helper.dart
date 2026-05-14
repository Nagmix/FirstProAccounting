import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  static const int _databaseVersion = 3;
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
        name_en TEXT NOT NULL,
        parent_id INTEGER,
        account_code TEXT NOT NULL,
        account_type TEXT NOT NULL DEFAULT 'ASSET',
        balance REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'SAR',
        is_active INTEGER NOT NULL DEFAULT 1,
        is_system INTEGER NOT NULL DEFAULT 0,
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
        tax_rate REAL NOT NULL DEFAULT 15.0,
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
        FOREIGN KEY (warehouse_id) REFERENCES warehouses (id),
        FOREIGN KEY (sales_account_id) REFERENCES accounts (id),
        FOREIGN KEY (purchase_account_id) REFERENCES accounts (id),
        FOREIGN KEY (inventory_account_id) REFERENCES accounts (id)
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
        country TEXT,
        credit_limit REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Invoices
    await db.execute('''
      CREATE TABLE invoices (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payment_type TEXT NOT NULL DEFAULT 'cash',
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
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id)
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
        currency TEXT NOT NULL DEFAULT 'SAR',
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

    // Complaints
    await db.execute('''
      CREATE TABLE complaints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        priority TEXT NOT NULL DEFAULT 'medium',
        assigned_to INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        FOREIGN KEY (assigned_to) REFERENCES users (id)
      )
    ''');

    // Surveys
    await db.execute('''
      CREATE TABLE surveys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Representatives
    await db.execute('''
      CREATE TABLE representatives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        area TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
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

    // --- Indexes ---
    await db.execute(
      'CREATE INDEX idx_products_barcode ON products (barcode)',
    );
    await db.execute(
      'CREATE INDEX idx_products_item_code ON products (item_code)',
    );
    await db.execute(
      'CREATE INDEX idx_invoices_customer_id ON invoices (customer_id)',
    );
    await db.execute(
      'CREATE INDEX idx_invoices_created_at ON invoices (created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_invoices_status ON invoices (status)',
    );
    await db.execute(
      'CREATE INDEX idx_invoice_items_invoice_id ON invoice_items (invoice_id)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_account_id ON transactions (account_id)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_journal_id ON transactions (journal_id)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_date ON transactions (date)',
    );
    await db.execute(
      'CREATE INDEX idx_accounts_account_code ON accounts (account_code)',
    );
    await db.execute(
      'CREATE INDEX idx_accounts_account_type ON accounts (account_type)',
    );
    await db.execute(
      'CREATE INDEX idx_products_category_id ON products (category_id)',
    );
    await db.execute(
      'CREATE INDEX idx_complaints_customer_id ON complaints (customer_id)',
    );
    await db.execute(
      'CREATE INDEX idx_notifications_is_read ON notifications (is_read)',
    );
    await db.execute(
      'CREATE INDEX idx_currencies_code ON currencies (code)',
    );

    // Seed default currencies
    await _seedCurrencies(db);
  }

  Future<void> _seedCurrencies(Database db) async {
    final now = DateTime.now().toIso8601String();
    final currencies = [
      {'code': 'SAR', 'name_ar': 'ريال سعودي', 'name_en': 'Saudi Riyal', 'symbol': 'ر.س', 'exchange_rate': 1.0, 'is_default': 1, 'is_active': 1, 'created_at': now},
      {'code': 'AED', 'name_ar': 'درهم إماراتي', 'name_en': 'UAE Dirham', 'symbol': 'د.إ', 'exchange_rate': 0.98, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'EGP', 'name_ar': 'جنيه مصري', 'name_en': 'Egyptian Pound', 'symbol': 'ج.م', 'exchange_rate': 0.12, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'IQD', 'name_ar': 'دينار عراقي', 'name_en': 'Iraqi Dinar', 'symbol': 'د.ع', 'exchange_rate': 0.0029, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'KWD', 'name_ar': 'دينار كويتي', 'name_en': 'Kuwaiti Dinar', 'symbol': 'د.ك', 'exchange_rate': 12.25, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'BHD', 'name_ar': 'دينار بحريني', 'name_en': 'Bahraini Dinar', 'symbol': 'د.ب', 'exchange_rate': 9.95, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'OMR', 'name_ar': 'ريال عماني', 'name_en': 'Omani Rial', 'symbol': 'ر.ع', 'exchange_rate': 9.72, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'QAR', 'name_ar': 'ريال قطري', 'name_en': 'Qatari Riyal', 'symbol': 'ر.ق', 'exchange_rate': 1.03, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'JOD', 'name_ar': 'دينار أردني', 'name_en': 'Jordanian Dinar', 'symbol': 'د.أ', 'exchange_rate': 5.18, 'is_default': 0, 'is_active': 1, 'created_at': now},
      {'code': 'USD', 'name_ar': 'دولار أمريكي', 'name_en': 'US Dollar', 'symbol': r'$', 'exchange_rate': 3.75, 'is_default': 0, 'is_active': 1, 'created_at': now},
    ];
    for (final c in currencies) {
      await db.insert('currencies', c);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns to products table for v2
      await db.execute(
          'ALTER TABLE products ADD COLUMN item_code TEXT');
      await db.execute(
          'ALTER TABLE products ADD COLUMN supplier_id INTEGER');
      await db.execute(
          'ALTER TABLE products ADD COLUMN group_id TEXT');
      await db.execute(
          'ALTER TABLE products ADD COLUMN description TEXT');
      await db.execute(
          'ALTER TABLE products ADD COLUMN special_wholesale_price REAL NOT NULL DEFAULT 0.0');
      await db.execute(
          'ALTER TABLE products ADD COLUMN minimum_sale_price REAL NOT NULL DEFAULT 0.0');
      await db.execute(
          'ALTER TABLE products ADD COLUMN sales_account_id INTEGER');
      await db.execute(
          'ALTER TABLE products ADD COLUMN purchase_account_id INTEGER');
      await db.execute(
          'ALTER TABLE products ADD COLUMN inventory_account_id INTEGER');
      await db.execute(
          'ALTER TABLE products ADD COLUMN warehouse_id INTEGER');
      await db.execute(
          'ALTER TABLE products ADD COLUMN weight REAL NOT NULL DEFAULT 0.0');
      await db.execute(
          'ALTER TABLE products ADD COLUMN notes TEXT');
      await db.execute(
          'ALTER TABLE products ADD COLUMN include_in_reports INTEGER NOT NULL DEFAULT 1');
      // Update default tax_rate from 0.0 to 15.0 for existing rows
      await db.execute(
          'UPDATE products SET tax_rate = 15.0 WHERE tax_rate = 0.0');
      // Add new index
      await db.execute(
          'CREATE INDEX idx_products_item_code ON products (item_code)');
    }
    if (oldVersion < 3) {
      // Add currencies table
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
        'CREATE INDEX IF NOT EXISTS idx_currencies_code ON currencies (code)',
      );
      // Add credit_limit column to customers
      await db.execute(
          'ALTER TABLE customers ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0.0');
      // Seed default currencies
      await _seedCurrencies(db);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Product CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// Insert a new product and return its id.
  Future<int> insertProduct(Map<String, dynamic> productMap) async {
    final db = await database;
    return await db.insert('products', productMap);
  }

  /// Get all products, optionally filtered by active status.
  Future<List<Map<String, dynamic>>> getAllProducts({
    bool? activeOnly,
    String orderBy = 'created_at DESC',
  }) async {
    final db = await database;
    if (activeOnly == true) {
      return await db.query(
        'products',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: orderBy,
      );
    }
    return await db.query('products', orderBy: orderBy);
  }

  /// Search products by name (Arabic/English) or barcode.
  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    final db = await database;
    final likeQuery = '%$query%';
    return await db.query(
      'products',
      where:
          'name_ar LIKE ? OR name_en LIKE ? OR barcode LIKE ? OR item_code LIKE ?',
      whereArgs: [likeQuery, likeQuery, likeQuery, likeQuery],
      orderBy: 'created_at DESC',
    );
  }

  /// Get a single product by id.
  Future<Map<String, dynamic>?> getProductById(int id) async {
    final db = await database;
    final results = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update a product by id.
  Future<int> updateProduct(int id, Map<String, dynamic> productMap) async {
    final db = await database;
    return await db
        .update('products', productMap, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete a product by id.
  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// Get the count of products.
  Future<int> getProductCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM products');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  /// Get the next auto-generated item code.
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

  /// Insert a new customer and return its id.
  Future<int> insertCustomer(Map<String, dynamic> customerMap) async {
    final db = await database;
    return await db.insert('customers', customerMap);
  }

  /// Get all customers.
  Future<List<Map<String, dynamic>>> getAllCustomers({
    String orderBy = 'created_at DESC',
  }) async {
    final db = await database;
    return await db.query('customers', orderBy: orderBy);
  }

  /// Search customers by name or phone.
  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    final db = await database;
    final likeQuery = '%$query%';
    return await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: [likeQuery, likeQuery],
      orderBy: 'created_at DESC',
    );
  }

  /// Get a single customer by id.
  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final db = await database;
    final results = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update a customer by id.
  Future<int> updateCustomer(int id, Map<String, dynamic> customerMap) async {
    final db = await database;
    return await db
        .update('customers', customerMap, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete a customer by id.
  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Currency CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// Insert a new currency and return its id.
  Future<int> insertCurrency(Map<String, dynamic> currencyMap) async {
    final db = await database;
    return await db.insert('currencies', currencyMap);
  }

  /// Get all currencies.
  Future<List<Map<String, dynamic>>> getAllCurrencies({
    String orderBy = 'is_default DESC, code ASC',
  }) async {
    final db = await database;
    return await db.query('currencies', orderBy: orderBy);
  }

  /// Get active currencies.
  Future<List<Map<String, dynamic>>> getActiveCurrencies() async {
    final db = await database;
    return await db.query(
      'currencies',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'is_default DESC, code ASC',
    );
  }

  /// Get default currency.
  Future<Map<String, dynamic>?> getDefaultCurrency() async {
    final db = await database;
    final results = await db.query(
      'currencies',
      where: 'is_default = ?',
      whereArgs: [1],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update a currency by id.
  Future<int> updateCurrency(int id, Map<String, dynamic> currencyMap) async {
    final db = await database;
    return await db
        .update('currencies', currencyMap, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete a currency by id.
  Future<int> deleteCurrency(int id) async {
    final db = await database;
    return await db.delete('currencies', where: 'id = ?', whereArgs: [id]);
  }

  /// Set a currency as default (unsets all others).
  Future<void> setDefaultCurrency(int id) async {
    final db = await database;
    await db.update('currencies', {'is_default': 0});
    await db.update('currencies', {'is_default': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Invoice CRUD methods
  // ══════════════════════════════════════════════════════════════

  /// Insert a new invoice with its items in a transaction.
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

  /// Get all invoices with customer/supplier name.
  Future<List<Map<String, dynamic>>> getAllInvoices({
    String orderBy = 'created_at DESC',
  }) async {
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

  /// Get invoices filtered by type.
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

  /// Get invoice items by invoice id.
  Future<List<Map<String, dynamic>>> getInvoiceItems(String invoiceId) async {
    final db = await database;
    return await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );
  }

  /// Delete an invoice by id.
  Future<int> deleteInvoice(String id) async {
    final db = await database;
    await db.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
    return await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  // ══════════════════════════════════════════════════════════════
  //  Category methods
  // ══════════════════════════════════════════════════════════════

  /// Get all active categories.
  Future<List<Map<String, dynamic>>> getAllCategories() async {
    final db = await database;
    return await db.query(
      'categories',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
  }

  /// Insert a new category.
  Future<int> insertCategory(Map<String, dynamic> categoryMap) async {
    final db = await database;
    return await db.insert('categories', categoryMap);
  }

  // ══════════════════════════════════════════════════════════════
  //  Supplier methods
  // ══════════════════════════════════════════════════════════════

  /// Get all suppliers.
  Future<List<Map<String, dynamic>>> getAllSuppliers() async {
    final db = await database;
    return await db.query('suppliers', orderBy: 'name ASC');
  }

  /// Insert a new supplier.
  Future<int> insertSupplier(Map<String, dynamic> supplierMap) async {
    final db = await database;
    return await db.insert('suppliers', supplierMap);
  }

  // ══════════════════════════════════════════════════════════════
  //  Warehouse methods
  // ══════════════════════════════════════════════════════════════

  /// Get all active warehouses.
  Future<List<Map<String, dynamic>>> getAllWarehouses() async {
    final db = await database;
    return await db.query(
      'warehouses',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
  }

  /// Insert a new warehouse.
  Future<int> insertWarehouse(Map<String, dynamic> warehouseMap) async {
    final db = await database;
    return await db.insert('warehouses', warehouseMap);
  }

  // ══════════════════════════════════════════════════════════════
  //  Account methods
  // ══════════════════════════════════════════════════════════════

  /// Get all active accounts.
  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await database;
    return await db.query(
      'accounts',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'account_code ASC',
    );
  }

  /// Get accounts filtered by type (e.g. 'REVENUE', 'EXPENSE', 'ASSET').
  Future<List<Map<String, dynamic>>> getAccountsByType(String accountType) async {
    final db = await database;
    return await db.query(
      'accounts',
      where: 'is_active = ? AND account_type = ?',
      whereArgs: [1, accountType],
      orderBy: 'account_code ASC',
    );
  }

  /// Insert a new account.
  Future<int> insertAccount(Map<String, dynamic> accountMap) async {
    final db = await database;
    return await db.insert('accounts', accountMap);
  }

  // ══════════════════════════════════════════════════════════════
  //  Settings methods
  // ══════════════════════════════════════════════════════════════

  /// Get a setting value by key.
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  /// Set a setting value.
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Dashboard query methods
  // ══════════════════════════════════════════════════════════════

  /// Returns the total sales amount for the given [date].
  Future<double> getTotalSalesForDate(DateTime date) async {
    final db = await database;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND date(created_at) = ?",
      [dateStr],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns the total purchase amount for the current month.
  Future<double> getTotalPurchasesThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final monthStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'purchase' AND date(created_at) >= ?",
      [monthStart],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns the total sales amount for the current month.
  Future<double> getTotalSalesThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final monthStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices WHERE type = 'sale' AND date(created_at) >= ?",
      [monthStart],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns the number of invoices created on the given [date].
  Future<int> getInvoiceCountForDate(DateTime date) async {
    final db = await database;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE date(created_at) = ?",
      [dateStr],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  /// Returns the total number of customers.
  Future<int> getCustomerCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) AS cnt FROM customers');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  /// Returns the cash balance.
  Future<double> getCashBalance() async {
    final db = await database;
    final salesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(paid_amount), 0.0) AS total FROM invoices WHERE type = 'sale' AND payment_type = 'cash'",
    );
    final purchaseResult = await db.rawQuery(
      "SELECT COALESCE(SUM(paid_amount), 0.0) AS total FROM invoices WHERE type = 'purchase' AND payment_type = 'cash'",
    );
    final salesCash =
        (salesResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final purchaseCash =
        (purchaseResult.first['total'] as num?)?.toDouble() ?? 0.0;
    return salesCash - purchaseCash;
  }

  /// Returns the most recent [limit] invoices with customer/supplier name.
  Future<List<Map<String, dynamic>>> getRecentInvoices({int limit = 5}) async {
    final db = await database;

    final sales = await db.rawQuery(
      '''
      SELECT i.id, i.type, i.total, i.paid_amount, i.remaining,
             i.status, i.created_at,
             COALESCE(c.name, 'بدون عميل') AS entity_name
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE i.type = 'sale'
      ORDER BY i.created_at DESC
      LIMIT ?
      ''',
      [limit],
    );

    final purchases = await db.rawQuery(
      '''
      SELECT i.id, i.type, i.total, i.paid_amount, i.remaining,
             i.status, i.created_at,
             COALESCE(s.name, 'بدون مورد') AS entity_name
      FROM invoices i
      LEFT JOIN suppliers s ON i.supplier_id = s.id
      WHERE i.type = 'purchase'
      ORDER BY i.created_at DESC
      LIMIT ?
      ''',
      [limit],
    );

    final all = [...sales, ...purchases];
    all.sort((a, b) {
      final dateA = DateTime.tryParse(a['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = DateTime.tryParse(b['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    return all.take(limit).toList();
  }

  /// Returns daily sales totals for the last [days] days.
  Future<List<Map<String, dynamic>>> getDailySalesTotals({int days = 7}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery(
      '''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type = 'sale' AND date(created_at) >= ?
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
      ''',
      [startDateStr],
    );
  }
}
