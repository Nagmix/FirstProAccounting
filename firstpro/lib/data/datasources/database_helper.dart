import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static const int _databaseVersion = 31;
  static const String _databaseName = 'firstpro.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _databaseFuture ??= initDatabase();
    _database = await _databaseFuture!;
    return _database!;
  }

  /// Close the current database connection and reset the singleton instance.
  /// Call this before replacing the DB file during a restore operation.
  Future<void> resetInstance() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _databaseFuture = null;
    }
  }

  /// Get the database file path (useful for backup/restore).
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _databaseName);
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
        average_cost REAL NOT NULL DEFAULT 0.0,
        sell_price REAL NOT NULL DEFAULT 0.0,
        wholesale_price REAL NOT NULL DEFAULT 0.0,
        special_wholesale_price REAL NOT NULL DEFAULT 0.0,
        minimum_sale_price REAL NOT NULL DEFAULT 0.0,
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

    // Customers
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        address2 TEXT,
        email TEXT,
        contact_method TEXT DEFAULT 'whatsapp',
        notes TEXT,
        balance REAL NOT NULL DEFAULT 0.0,
        balance_type TEXT NOT NULL DEFAULT 'credit',
        currency TEXT NOT NULL DEFAULT 'YER',
        debt_ceiling REAL NOT NULL DEFAULT 0.0,
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
        original_invoice_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
        FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
        FOREIGN KEY (original_invoice_id) REFERENCES invoices (id)
      )
    ''');

    // Units Master
    await db.execute('''
      CREATE TABLE units (
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
    await db.execute('CREATE INDEX idx_units_type ON units (unit_type)');
    await db.execute('CREATE INDEX idx_units_active ON units (is_active)');

    // Invoice Items (v25: added unit_name, conversion_factor, base_quantity)
    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1.0,
        unit_price REAL NOT NULL DEFAULT 0.0,
        total_price REAL NOT NULL DEFAULT 0.0,
        unit_name TEXT,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        base_quantity REAL NOT NULL DEFAULT 1.0,
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
        balance_type TEXT NOT NULL DEFAULT 'credit',
        currency TEXT NOT NULL DEFAULT 'YER',
        notes TEXT,
        debt_ceiling REAL NOT NULL DEFAULT 0.0,
        contact_method TEXT DEFAULT 'whatsapp',
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_original ON invoices (original_invoice_id)');
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

    // Seed default units
    await _seedDefaultUnits(db);
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

    // Vouchers (السندات) - v18
    await db.execute('''
      CREATE TABLE vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucher_number TEXT NOT NULL,
        voucher_type TEXT NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        currency TEXT NOT NULL DEFAULT 'YER',
        total_amount REAL NOT NULL DEFAULT 0.0,
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

    // Voucher line items (بنود السند) - v18
    await db.execute('''
      CREATE TABLE voucher_items (
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

    // Stock Transfers (تحويل مخزني) - v19
    await db.execute('''
      CREATE TABLE stock_transfers (
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

    // Stocktaking Sessions (جرد المخازن) - v19
    await db.execute('''
      CREATE TABLE stocktaking_sessions (
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

    // Stocktaking Items (عناصر الجرد) - v19 (v30: added variance)
    await db.execute('''
      CREATE TABLE stocktaking_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        system_quantity REAL NOT NULL,
        actual_quantity REAL NOT NULL,
        difference REAL NOT NULL,
        variance REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (session_id) REFERENCES stocktaking_sessions (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    // v18 indexes
    await db.execute('CREATE INDEX idx_vouchers_voucher_number ON vouchers (voucher_number)');
    await db.execute('CREATE INDEX idx_vouchers_voucher_type ON vouchers (voucher_type)');
    await db.execute('CREATE INDEX idx_vouchers_date ON vouchers (date)');
    await db.execute('CREATE INDEX idx_vouchers_created_at ON vouchers (created_at)');
    await db.execute('CREATE INDEX idx_voucher_items_voucher_id ON voucher_items (voucher_id)');
    await db.execute('CREATE INDEX idx_voucher_items_account_id ON voucher_items (account_id)');
    // v19 indexes
    await db.execute('CREATE INDEX idx_stock_transfers_number ON stock_transfers (transfer_number)');
    await db.execute('CREATE INDEX idx_stock_transfers_from_wh ON stock_transfers (from_warehouse_id)');
    await db.execute('CREATE INDEX idx_stock_transfers_to_wh ON stock_transfers (to_warehouse_id)');
    await db.execute('CREATE INDEX idx_stock_transfers_product ON stock_transfers (product_id)');
    await db.execute('CREATE INDEX idx_stock_transfers_date ON stock_transfers (date)');
    await db.execute('CREATE INDEX idx_stocktaking_sessions_number ON stocktaking_sessions (session_number)');
    await db.execute('CREATE INDEX idx_stocktaking_sessions_wh ON stocktaking_sessions (warehouse_id)');
    await db.execute('CREATE INDEX idx_stocktaking_items_session ON stocktaking_items (session_id)');

    // Inventory Vouchers (سندات الجرد) - v22
    await db.execute('''
      CREATE TABLE inventory_vouchers (
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

    // Inventory Voucher Items (بنود سند الجرد) - v22
    await db.execute('''
      CREATE TABLE inventory_voucher_items (
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

    // Fiscal Years (السنوات المالية) - v22
    await db.execute('''
      CREATE TABLE fiscal_years (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL UNIQUE,
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
    await db.execute('CREATE INDEX idx_inventory_vouchers_number ON inventory_vouchers (voucher_number)');
    await db.execute('CREATE INDEX idx_inventory_vouchers_date ON inventory_vouchers (date)');
    await db.execute('CREATE INDEX idx_inventory_vouchers_warehouse ON inventory_vouchers (warehouse_id)');
    await db.execute('CREATE INDEX idx_inventory_vouchers_status ON inventory_vouchers (status)');
    await db.execute('CREATE INDEX idx_inventory_voucher_items_voucher ON inventory_voucher_items (voucher_id)');
    await db.execute('CREATE INDEX idx_inventory_voucher_items_product ON inventory_voucher_items (product_id)');
    await db.execute('CREATE INDEX idx_fiscal_years_year ON fiscal_years (year)');
    await db.execute('CREATE INDEX idx_fiscal_years_status ON fiscal_years (status)');

    // Audit Trail - v29
    await db.execute('''
      CREATE TABLE audit_trail (
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
    await db.execute('CREATE INDEX idx_audit_trail_table ON audit_trail (table_name)');
    await db.execute('CREATE INDEX idx_audit_trail_action ON audit_trail (action)');
    await db.execute('CREATE INDEX idx_audit_trail_created ON audit_trail (created_at)');
    await db.execute('CREATE INDEX idx_audit_trail_record ON audit_trail (table_name, record_id)');

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
        'balance_type': (type == 'ASSET' || type == 'COST') ? 'debit' : 'credit',
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
      ['المخزون', 'Inventory Account', '1300', 'ASSET'],
      ['حساب الخصوم', 'Liabilities Account', '2000', 'LIABILITY'],
      ['حساب الموردين', 'Suppliers Account', '2100', 'LIABILITY'],
      ['رصيد افتتاحي', 'Opening Balance Equity', '2200', 'LIABILITY'],
      ['الأرباح المحتجزة', 'Retained Earnings', '2900', 'LIABILITY'],
      ['ضريبة القيمة المضافة', 'VAT Payable', '3300', 'LIABILITY'],
      ['تكلفة البضاعة المباعة', 'COGS Account', '3200', 'COST'],
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
      ['المخزون', 'Inventory Account', 1300, 'ASSET'],
      ['حساب الخصوم', 'Liabilities Account', 2000, 'LIABILITY'],
      ['حساب الموردين', 'Suppliers Account', 2100, 'LIABILITY'],
      ['رصيد افتتاحي', 'Opening Balance Equity', 2200, 'LIABILITY'],
      ['الأرباح المحتجزة', 'Retained Earnings', 2900, 'LIABILITY'],
      ['ضريبة القيمة المضافة', 'VAT Payable', 3300, 'LIABILITY'],
      ['تكلفة البضاعة المباعة', 'COGS Account', 3200, 'COST'],
      ['حساب المشتريات', 'Purchases Account', 3100, 'COST'],
      ['حساب المبيعات', 'Sales Account', 4100, 'REVENUE'],
      ['حساب المصاريف', 'Expenses Account', 5000, 'EXPENSE'],
      ['اجور النقل', 'Transport Charges', 5200, 'EXPENSE'],
      ['حساب الموظفين', 'Employees Account', 5100, 'EXPENSE'],
    ];

    for (final template in templates) {
      final actualCode = ((template[2] as int) + codeOffset).toString();
      final accountType = template[3] as String;
      await db.insert('accounts', {
        'name_ar': '${template[0]} ($currencySymbol)',
        'name_en': '${template[1]} ($currencyCode)',
        'account_code': actualCode,
        'account_type': accountType,
        'balance': 0.0,
        'currency': currencyCode,
        'balance_type': (accountType == 'ASSET' || accountType == 'COST') ? 'debit' : 'credit',
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

      // Add balance_type to suppliers (default 'credit' because we typically owe the supplier)
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\''); } catch (_) {}

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

    if (oldVersion < 18) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_voucher_number ON vouchers (voucher_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_voucher_type ON vouchers (voucher_type)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_date ON vouchers (date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_created_at ON vouchers (created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_voucher_items_voucher_id ON voucher_items (voucher_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_voucher_items_account_id ON voucher_items (account_id)');
    }

    // ══════════════════════════════════════════════════════════════
    //  v19 Migration: Stock Transfers & Stocktaking
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 19) {
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

      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_transfers_number ON stock_transfers (transfer_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_transfers_from_wh ON stock_transfers (from_warehouse_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_transfers_to_wh ON stock_transfers (to_warehouse_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_transfers_product ON stock_transfers (product_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_transfers_date ON stock_transfers (date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stocktaking_sessions_number ON stocktaking_sessions (session_number)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stocktaking_sessions_wh ON stocktaking_sessions (warehouse_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stocktaking_items_session ON stocktaking_items (session_id)');
    }

    // ══════════════════════════════════════════════════════════════
    //  v20 Migration: Fix supplier balance_type default, add debt_ceiling
    //  to suppliers, add customer_id/supplier_id to vouchers, seed new
    //  accounts (COGS, Inventory, Retained Earnings, Opening Balance Equity)
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 20) {
      // Add debt_ceiling column to suppliers
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (_) {}

      // Add contact_method column to suppliers
      try { await db.execute("ALTER TABLE suppliers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (_) {}

      // Fix supplier balance_type default to 'credit' (we typically owe the supplier)
      try { await db.execute("UPDATE suppliers SET balance_type = 'credit' WHERE balance_type = 'debit' AND balance >= 0"); } catch (_) {}

      // Add customer_id and supplier_id columns to vouchers
      try { await db.execute('ALTER TABLE vouchers ADD COLUMN customer_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE vouchers ADD COLUMN supplier_id INTEGER'); } catch (_) {}

      // Seed new accounts for each currency if they don't exist
      final now20 = DateTime.now().toIso8601String();
      final newAccountTemplates = [
        // Inventory account (ASSET, code 1300+offset)
        {'baseCode': 1300, 'nameAr': 'المخزون', 'nameEn': 'Inventory Account', 'type': 'ASSET'},
        // Opening Balance Equity (LIABILITY, code 2200+offset)
        {'baseCode': 2200, 'nameAr': 'رصيد افتتاحي', 'nameEn': 'Opening Balance Equity', 'type': 'LIABILITY'},
        // Retained Earnings (LIABILITY, code 2900+offset)
        {'baseCode': 2900, 'nameAr': 'الأرباح المحتجزة', 'nameEn': 'Retained Earnings', 'type': 'LIABILITY'},
        // COGS account (COST, code 3200+offset)
        {'baseCode': 3200, 'nameAr': 'تكلفة البضاعة المباعة', 'nameEn': 'COGS Account', 'type': 'COST'},
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
          final actualCode = ((template['baseCode'] as int) + codeOffset).toString();
          final existing = await db.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [actualCode, currencyCode], limit: 1);
          if (existing.isEmpty) {
            await db.insert('accounts', {
              'name_ar': '${template['nameAr']} ($currencySymbol)',
              'name_en': '${template['nameEn']} ($currencyCode)',
              'account_code': actualCode,
              'account_type': template['type'],
              'balance': 0.0,
              'currency': currencyCode,
              'is_active': 1,
              'is_system': 1,
              'debt_ceiling': 0.0,
              'balance_type': 'credit',
              'created_at': now20,
              'updated_at': now20,
            });
          }
        }
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  v21 Migration: Add contact_method and debt_ceiling to customers
    //  (replacing notification_method and credit_limit fields)
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 21) {
      // Add contact_method column to customers (replacing notification_method)
      try { await db.execute("ALTER TABLE customers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (_) {}

      // Add debt_ceiling column to customers (replacing credit_limit)
      try { await db.execute('ALTER TABLE customers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (_) {}

      // Copy data from old columns to new columns
      try { await db.execute("UPDATE customers SET contact_method = COALESCE(notification_method, 'whatsapp') WHERE contact_method IS NULL OR contact_method = 'whatsapp'"); } catch (_) {}
      try { await db.execute('UPDATE customers SET debt_ceiling = COALESCE(credit_limit, 0.0) WHERE debt_ceiling = 0.0'); } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v23 Migration: Add UNIQUE constraint on fiscal_years.year
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 23) {
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

    // ══════════════════════════════════════════════════════════════
    //  v24 Migration: Fix balance_type + Multi-Unit + Weighted Average Cost
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 24) {
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
          'SELECT COALESCE(SUM(debit) - SUM(credit), 0.0) AS net_debit FROM transactions WHERE account_id = ?',
          [accountId],
        );
        final correctBalance = (txResult.first['net_debit'] as num?)?.toDouble() ?? 0.0;
        await db.update(
          'accounts',
          {'balance': correctBalance, 'updated_at': DateTime.now().toIso8601String()},
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
      } catch (_) {}
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

    // ══════════════════════════════════════════════════════════════
    //  v22 Migration: Inventory Vouchers & Fiscal Years
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 22) {
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

    // ══════════════════════════════════════════════════════════════
    //  v25 Migration: Units Master + Product Unit Fields + Invoice Item Unit Fields
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 25) {
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
      await _seedDefaultUnits(db);

      // ── Add new product columns for unit management ──
      try { await db.execute('ALTER TABLE products ADD COLUMN base_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN purchase_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN sale_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN tax_inclusive INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN allow_negative INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN sell_retail INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN show_in_pos INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT'); } catch (_) {}

      // Migrate existing unit_id → base_unit_id
      await db.execute('UPDATE products SET base_unit_id = unit_id WHERE base_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET sale_unit_id = unit_id WHERE sale_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET purchase_unit_id = unit_id WHERE purchase_unit_id IS NULL AND unit_id IS NOT NULL');

      // ── Add unit fields to invoice_items ──
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_name TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1.0'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN base_quantity REAL NOT NULL DEFAULT 1.0'); } catch (_) {}

      // Backfill base_quantity from quantity for existing invoice items
      await db.execute('UPDATE invoice_items SET base_quantity = quantity WHERE base_quantity = 1.0 AND quantity != 1.0');

      // ── Update unit_conversions to use unit IDs ──
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN from_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN to_unit_id INTEGER'); } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v26 Migration: Ensure ALL missing columns exist (fixes databases
    //  created with broken _onCreate that lacked average_cost etc.)
    //  Also adds VAT account (code 3300) for each currency.
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 26) {
      // ── Products table: add missing columns ──
      try { await db.execute('ALTER TABLE products ADD COLUMN average_cost REAL NOT NULL DEFAULT 0.0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN tax_inclusive INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN expiry_tracking INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN has_variants INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN base_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN purchase_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN sale_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN allow_negative INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN sell_retail INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN show_in_pos INTEGER NOT NULL DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT'); } catch (_) {}

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
      await _seedDefaultUnits(db);

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
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_name TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1.0'); } catch (_) {}
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN base_quantity REAL NOT NULL DEFAULT 1.0'); } catch (_) {}

      // ── Add debt_ceiling and contact_method to customers ──
      try { await db.execute('ALTER TABLE customers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (_) {}
      try { await db.execute("ALTER TABLE customers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (_) {}

      // ── Add debt_ceiling and contact_method to suppliers ──
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (_) {}
      try { await db.execute("ALTER TABLE suppliers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (_) {}

      // ── Add operation_type and expense_account_id to expenses ──
      try { await db.execute("ALTER TABLE expenses ADD COLUMN operation_type TEXT NOT NULL DEFAULT 'صرف'"); } catch (_) {}
      try { await db.execute('ALTER TABLE expenses ADD COLUMN expense_account_id INTEGER'); } catch (_) {}

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
            'balance': 0.0,
            'currency': currencyCode,
            'is_active': 1,
            'is_system': 1,
            'debt_ceiling': 0.0,
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

    // ══════════════════════════════════════════════════════════════
    //  v27 Migration: Add cogs_account_id and vat_account_id to products
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 27) {
      try { await db.execute('ALTER TABLE products ADD COLUMN cogs_account_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE products ADD COLUMN vat_account_id INTEGER'); } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v28 Migration: Ensure from_unit_id and to_unit_id exist in unit_conversions
    //  (was missing from _onCreate in earlier versions)
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 28) {
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN from_unit_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN to_unit_id INTEGER'); } catch (_) {}
    }

    // ══════════════════════════════════════════════════════════════
    //  v29 Migration: Add audit_trail table
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 29) {
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
    if (oldVersion < 30) {
      try {
        await db.execute('ALTER TABLE stocktaking_items ADD COLUMN variance REAL NOT NULL DEFAULT 0.0');
      } catch (_) {}
    }
    if (oldVersion < 31) {
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN original_invoice_id TEXT');
      } catch (_) {}
      await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_original ON invoices (original_invoice_id)');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Seed Default Units
  // ══════════════════════════════════════════════════════════════

  /// Seed the units table with a comprehensive default set organized by type.
  Future<void> _seedDefaultUnits(Database db) async {
    final now = DateTime.now().toIso8601String();
    // Only seed if units table is empty
    final count = (await db.query('units')).length;
    if (count > 0) return;

    final defaultUnits = [
      // ── العد (Count) ──
      {'name_ar': 'حبة', 'name_en': 'Piece', 'abbreviation': 'حبة', 'unit_type': 'count', 'is_base_unit': 1, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 1},
      {'name_ar': 'قطعة', 'name_en': 'Item', 'abbreviation': 'ق', 'unit_type': 'count', 'is_base_unit': 1, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 2},
      {'name_ar': 'كرتون', 'name_en': 'Carton', 'abbreviation': 'كرت', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 3},
      {'name_ar': 'باكيت', 'name_en': 'Packet', 'abbreviation': 'باك', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 4},
      {'name_ar': 'علبة', 'name_en': 'Box', 'abbreviation': 'علب', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 5},
      {'name_ar': 'ظرف', 'name_en': 'Envelope', 'abbreviation': 'ظرف', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 6},
      {'name_ar': 'طبق', 'name_en': 'Tray', 'abbreviation': 'طبق', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 7},
      {'name_ar': 'طقم', 'name_en': 'Set', 'abbreviation': 'طقم', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 8},
      {'name_ar': 'منصة', 'name_en': 'Pallet', 'abbreviation': 'منص', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 0, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 9},
      {'name_ar': 'درزن', 'name_en': 'Dozen', 'abbreviation': 'درز', 'unit_type': 'count', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 10},

      // ── الوزن (Weight) ──
      {'name_ar': 'جرام', 'name_en': 'Gram', 'abbreviation': 'جم', 'unit_type': 'weight', 'is_base_unit': 1, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 11},
      {'name_ar': 'كيلو', 'name_en': 'Kilogram', 'abbreviation': 'كجم', 'unit_type': 'weight', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 12},
      {'name_ar': 'طن', 'name_en': 'Ton', 'abbreviation': 'طن', 'unit_type': 'weight', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 13},

      // ── السوائل (Liquid) ──
      {'name_ar': 'مل', 'name_en': 'Milliliter', 'abbreviation': 'مل', 'unit_type': 'liquid', 'is_base_unit': 1, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 14},
      {'name_ar': 'لتر', 'name_en': 'Liter', 'abbreviation': 'ل', 'unit_type': 'liquid', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 15},
      {'name_ar': 'جالون', 'name_en': 'Gallon', 'abbreviation': 'جال', 'unit_type': 'liquid', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 16},

      // ── الصيدلية (Pharmacy) ──
      {'name_ar': 'شريط', 'name_en': 'Strip', 'abbreviation': 'شر', 'unit_type': 'pharmacy', 'is_base_unit': 0, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 1, 'display_order': 17},
      {'name_ar': 'كبسولة', 'name_en': 'Capsule', 'abbreviation': 'كبس', 'unit_type': 'pharmacy', 'is_base_unit': 1, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 18},

      // ── القياس (Measurement) ──
      {'name_ar': 'متر', 'name_en': 'Meter', 'abbreviation': 'م', 'unit_type': 'count', 'is_base_unit': 1, 'is_sellable': 1, 'is_purchasable': 1, 'is_packaging': 0, 'display_order': 19},
    ];

    for (final unit in defaultUnits) {
      await db.insert('units', {
        ...unit,
        'is_active': 1,
        'description': '',
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Helper: Update account balance considering balance_type
  // ══════════════════════════════════════════════════════════════

  /// Public helper to update account balance by amount.
  /// [isDebit] = true means this is a debit entry (increase for debit-balance accounts).
  /// [isDebit] = false means this is a credit entry (increase for credit-balance accounts).
  Future<void> updateAccountBalance(int accountId, double amount, {required bool isDebit}) async {
    final db = await database;
    final account = await db.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (account.isNotEmpty) {
      final currentBalance = (account.first['balance'] as num?)?.toDouble() ?? 0.0;
      final balanceType = account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        // Credit-balance accounts: credit increases, debit decreases
        newBalance = isDebit ? currentBalance - amount : currentBalance + amount;
      } else {
        // Debit-balance accounts: debit increases, credit decreases
        newBalance = isDebit ? currentBalance + amount : currentBalance - amount;
      }
      await db.update('accounts', {
        'balance': newBalance,
        'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [accountId]);
    }
  }

  /// Update an account's balance considering its balance_type.
  /// For credit-balance accounts (LIABILITY, REVENUE, most EXPENSE):
  ///   balance = balance + credit - debit
  /// For debit-balance accounts (ASSET, COST):
  ///   balance = balance + debit - credit
  Future<void> _updateAccountBalanceWithJournal(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final account = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (account.isNotEmpty) {
      final currentBalance = (account.first['balance'] as num?)?.toDouble() ?? 0.0;
      final balanceType = account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        newBalance = currentBalance + credit - debit;
      } else {
        newBalance = currentBalance + debit - credit;
      }
      await txn.update('accounts', {'balance': newBalance, 'updated_at': now}, where: 'id = ?', whereArgs: [accountId]);
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
    // Check if product allows negative stock
    final productRow = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    final allowNegative = productRow.isNotEmpty ? (productRow.first['allow_negative'] as int?) == 1 : false;
    if (allowNegative) {
      await db.rawUpdate(
        'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
        [quantity, now, productId],
      );
    } else {
      await db.rawUpdate(
        'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
        [quantity, now, productId],
      );
    }
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

  /// Check if an item_code already exists in the products table.
  /// Optionally exclude a product ID (for edit mode).
  Future<bool> checkItemCodeExists(String code, {int? excludeId}) async {
    final db = await database;
    if (code.trim().isEmpty) return false;
    List<Map<String, dynamic>> result;
    if (excludeId != null) {
      result = await db.query(
        'products',
        where: 'item_code = ? AND id != ?',
        whereArgs: [code.trim(), excludeId],
        limit: 1,
      );
    } else {
      result = await db.query(
        'products',
        where: 'item_code = ?',
        whereArgs: [code.trim()],
        limit: 1,
      );
    }
    return result.isNotEmpty;
  }

  // ══════════════════════════════════════════════════════════════
  //  Customer CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCustomer(Map<String, dynamic> customerMap) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final openingBalance = (customerMap['balance'] as num?)?.toDouble() ?? 0.0;
    final balanceType = customerMap['balance_type'] as String? ?? 'credit';
    final customerCurrency = customerMap['currency'] as String? ?? 'YER';

    int? customerId;
    await db.transaction((txn) async {
      customerId = await txn.insert('customers', customerMap);

      // ── Opening Balance Journal Entry ──
      if (openingBalance > 0) {
        final journalId = DateTime.now().millisecondsSinceEpoch;
        final codeOffset = customerCurrency == 'SAR' ? 1 : (customerCurrency == 'USD' ? 2 : 0);

        final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), customerCurrency], limit: 1);
        final openingBalanceAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2200 + codeOffset).toString(), customerCurrency], limit: 1);

        final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (customersAccountId != null && openingBalanceAccountId != null) {
          if (balanceType == 'debit') {
            // Customer has debit (عليه) opening balance: Debit Customers, Credit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': openingBalance,
              'credit': 0.0,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': openingBalance,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, customersAccountId, openingBalance, 0.0, now);
            await _updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, openingBalance, now);
          } else {
            // Customer has credit (له) opening balance: Credit Customers, Debit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': openingBalance,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': openingBalance,
              'credit': 0.0,
              'description': 'رصيد افتتاحي عميل - ${customerMap['name']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, openingBalance, now);
            await _updateAccountBalanceWithJournal(txn, openingBalanceAccountId, openingBalance, 0.0, now);
          }
        }
      }
    });
    return customerId!;
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
    final now = DateTime.now().toIso8601String();
    final openingBalance = (supplierMap['balance'] as num?)?.toDouble() ?? 0.0;
    final balanceType = supplierMap['balance_type'] as String? ?? 'credit';
    final supplierCurrency = supplierMap['currency'] as String? ?? 'YER';

    int? supplierId;
    await db.transaction((txn) async {
      supplierId = await txn.insert('suppliers', supplierMap);

      // ── Opening Balance Journal Entry ──
      if (openingBalance > 0) {
        final journalId = DateTime.now().millisecondsSinceEpoch;
        final codeOffset = supplierCurrency == 'SAR' ? 1 : (supplierCurrency == 'USD' ? 2 : 0);

        final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), supplierCurrency], limit: 1);
        final openingBalanceAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2200 + codeOffset).toString(), supplierCurrency], limit: 1);

        final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;
        final openingBalanceAccountId = openingBalanceAccount.isNotEmpty ? openingBalanceAccount.first['id'] as int : null;

        if (suppliersAccountId != null && openingBalanceAccountId != null) {
          if (balanceType == 'credit') {
            // Supplier has credit (له) opening balance: Credit Suppliers, Debit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': openingBalance,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': openingBalance,
              'credit': 0.0,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, suppliersAccountId, 0.0, openingBalance, now);
            await _updateAccountBalanceWithJournal(txn, openingBalanceAccountId, openingBalance, 0.0, now);
          } else {
            // Supplier has debit (عليه) opening balance: Debit Suppliers, Credit Opening Balance Equity
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': openingBalance,
              'credit': 0.0,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await txn.insert('transactions', {
              'account_id': openingBalanceAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': openingBalance,
              'description': 'رصيد افتتاحي مورد - ${supplierMap['name']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, suppliersAccountId, openingBalance, 0.0, now);
            await _updateAccountBalanceWithJournal(txn, openingBalanceAccountId, 0.0, openingBalance, now);
          }
        }
      }
    });
    return supplierId!;
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

  /// Get all invoices for a specific supplier.
  Future<List<Map<String, dynamic>>> getSupplierInvoices(int supplierId) async {
    final db = await database;
    return await db.query(
      'invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get all vouchers for a specific supplier.
  Future<List<Map<String, dynamic>>> getSupplierVouchers(int supplierId) async {
    final db = await database;
    return await db.query(
      'vouchers',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
  }

  /// Get all financial movements for a supplier (invoices + vouchers) sorted by date.
  Future<List<Map<String, dynamic>>> getSupplierMovements(int supplierId) async {
    final db = await database;

    // Get invoices for this supplier
    final invoices = await db.query(
      'invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
    );

    // Get vouchers for this supplier
    final vouchers = await db.query(
      'vouchers',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );

    // Tag each entry with its source
    final movements = <Map<String, dynamic>>[];
    for (final inv in invoices) {
      movements.add({
        ...inv,
        '_source': 'invoice',
        '_sort_date': inv['created_at'] ?? '',
      });
    }
    for (final v in vouchers) {
      movements.add({
        ...v,
        '_source': 'voucher',
        '_sort_date': v['date'] ?? v['created_at'] ?? '',
      });
    }

    // Sort by date descending
    movements.sort((a, b) {
      final dateA = a['_sort_date'] as String? ?? '';
      final dateB = b['_sort_date'] as String? ?? '';
      return dateB.compareTo(dateA);
    });

    return movements;
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
  //  Units Master (CRUD)
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllUnits({String? unitType, bool activeOnly = false}) async {
    final db = await database;
    String? where;
    List<Object>? whereArgs;
    if (unitType != null && activeOnly) {
      where = 'unit_type = ? AND is_active = 1';
      whereArgs = [unitType];
    } else if (unitType != null) {
      where = 'unit_type = ?';
      whereArgs = [unitType];
    } else if (activeOnly) {
      where = 'is_active = 1';
    }
    return await db.query('units', where: where, whereArgs: whereArgs, orderBy: 'display_order ASC, id ASC');
  }

  Future<Map<String, dynamic>?> getUnitById(int id) async {
    final db = await database;
    final results = await db.query('units', where: 'id = ?', whereArgs: [id], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> insertUnit(Map<String, dynamic> unitMap) async {
    final db = await database;
    return await db.insert('units', unitMap);
  }

  Future<int> updateUnit(int id, Map<String, dynamic> unitMap) async {
    final db = await database;
    return await db.update('units', unitMap, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteUnit(int id) async {
    final db = await database;
    // Check if unit is used by any product
    final productsWithUnit = await db.query(
      'products',
      where: 'base_unit_id = ? OR purchase_unit_id = ? OR sale_unit_id = ? OR unit_id = ?',
      whereArgs: [id, id, id, id],
      limit: 1,
    );
    if (productsWithUnit.isNotEmpty) {
      throw Exception('لا يمكن حذف الوحدة لأنها مستخدمة في أصناف موجودة');
    }
    return await db.delete('units', where: 'id = ?', whereArgs: [id]);
  }

  /// Get unit name by ID from the units table
  Future<String> getUnitNameById(int unitId) async {
    final db = await database;
    final results = await db.query('units', where: 'id = ?', whereArgs: [unitId], limit: 1);
    if (results.isNotEmpty) {
      return results.first['name_ar'] as String? ?? '';
    }
    // Fallback to old static mapping for backward compat
    return _getUnitName(unitId);
  }

  // ══════════════════════════════════════════════════════════════
  //  Unit Conversions (Multi-Unit support)
  // ══════════════════════════════════════════════════════════════

  /// Insert a unit conversion for a product (e.g., 1 carton = 24 pieces)
  Future<int> insertUnitConversion(Map<String, dynamic> conversionMap) async {
    final db = await database;
    return await db.insert('unit_conversions', conversionMap);
  }

  /// Get all unit conversions for a product
  Future<List<Map<String, dynamic>>> getUnitConversions(int productId) async {
    final db = await database;
    return await db.query(
      'unit_conversions',
      where: 'product_id = ? AND is_active = 1',
      whereArgs: [productId],
      orderBy: 'id ASC',
    );
  }

  /// Update a unit conversion
  Future<int> updateUnitConversion(int id, Map<String, dynamic> conversionMap) async {
    final db = await database;
    return await db.update('unit_conversions', conversionMap, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete a unit conversion
  Future<int> deleteUnitConversion(int id) async {
    final db = await database;
    return await db.delete('unit_conversions', where: 'id = ?', whereArgs: [id]);
  }

  /// Find unit conversion by barcode (for POS barcode scanning)
  Future<Map<String, dynamic>?> findUnitConversionByBarcode(String barcode) async {
    final db = await database;
    final results = await db.query(
      'unit_conversions',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all available units for a product (base unit + conversions)
  /// Returns a list of maps with: {unit_name, conversion_factor, sell_price, barcode, unit_id, is_base}
  Future<List<Map<String, dynamic>>> getAvailableUnitsForProduct(int productId) async {
    final db = await database;
    // Get base product info
    final product = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (product.isEmpty) return [];

    // Resolve base unit name from units table (fallback to static mapping)
    final baseUnitId = product.first['base_unit_id'] as int? ?? product.first['unit_id'] as int? ?? 1;
    String baseUnitName;
    final unitRow = await db.query('units', where: 'id = ?', whereArgs: [baseUnitId], limit: 1);
    if (unitRow.isNotEmpty) {
      baseUnitName = unitRow.first['name_ar'] as String? ?? '';
    } else {
      baseUnitName = _getUnitName(baseUnitId);
    }
    final baseSellPrice = (product.first['sell_price'] as num?)?.toDouble() ?? 0.0;

    // Start with base unit (factor = 1.0)
    final units = <Map<String, dynamic>>[
      {
        'unit_name': baseUnitName,
        'conversion_factor': 1.0,
        'sell_price': baseSellPrice,
        'barcode': product.first['barcode'] as String? ?? '',
        'is_base': 1,
        'unit_id': baseUnitId,
      },
    ];

    // Add converted units
    final conversions = await db.query(
      'unit_conversions',
      where: 'product_id = ? AND is_active = 1',
      whereArgs: [productId],
    );
    for (final conv in conversions) {
      final fromUnit = conv['from_unit'] as String? ?? '';
      final factor = (conv['conversion_factor'] as num?)?.toDouble() ?? 1.0;
      final convSellPrice = (conv['sell_price'] as num?)?.toDouble() ?? (baseSellPrice * factor);
      // Resolve unit_id from the conversion if available
      final fromUnitId = conv['from_unit_id'] as int?;
      units.add({
        'unit_name': fromUnit,
        'conversion_factor': factor,
        'sell_price': convSellPrice,
        'barcode': conv['barcode'] as String? ?? '',
        'is_base': 0,
        'conversion_id': conv['id'],
        if (fromUnitId != null) 'unit_id': fromUnitId,
      });
    }
    return units;
  }

  /// Helper: Get unit name from unit_id (matches static list in add_product_sheet)
  String _getUnitName(int unitId) {
    const units = {
      1: 'قطعة', 2: 'كيلو', 3: 'لتر', 4: 'متر',
      5: 'علبة', 6: 'كرتون', 7: 'طن', 8: 'جرام',
    };
    return units[unitId] ?? 'قطعة';
  }

  // ══════════════════════════════════════════════════════════════
  //  Weighted Average Cost
  // ══════════════════════════════════════════════════════════════

  /// Update weighted average cost when purchasing at a new price.
  /// Formula: new_avg_cost = (existing_stock * old_avg_cost + new_qty * new_cost) / (existing_stock + new_qty)
  Future<void> updateWeightedAverageCost(int productId, double purchasedQty, double purchasedUnitCost) async {
    if (purchasedQty <= 0) return;
    final db = await database;
    final product = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (product.isEmpty) return;

    final currentStock = (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
    final currentAvgCost = (product.first['average_cost'] as num?)?.toDouble() ?? 0.0;

    final newTotalValue = (currentStock * currentAvgCost) + (purchasedQty * purchasedUnitCost);
    final newTotalStock = currentStock + purchasedQty;
    final newAvgCost = newTotalStock > 0 ? newTotalValue / newTotalStock : purchasedUnitCost;

    await db.update(
      'products',
      {
        'average_cost': newAvgCost,
        'cost_price': newAvgCost,  // Keep cost_price in sync for backward compatibility
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Stock Movement Log
  // ══════════════════════════════════════════════════════════════

  /// Log a stock movement for audit trail
  /// movement_type: 'sale', 'purchase', 'return', 'adjustment', 'transfer', 'opening', 'damage'
  Future<int> logStockMovement({
    required int productId,
    required String movementType,
    required double quantity,
    String? referenceType,
    String? referenceId,
    String? notes,
    double unitCost = 0.0,
  }) async {
    final db = await database;
    return await db.insert('stock_movements', {
      'product_id': productId,
      'movement_type': movementType,
      'quantity': quantity,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'unit_cost': unitCost,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get stock movement history for a product
  Future<List<Map<String, dynamic>>> getStockMovements(int productId, {int limit = 50}) async {
    final db = await database;
    return await db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// Get stock movements by type (e.g., all sales today)
  Future<List<Map<String, dynamic>>> getStockMovementsByType(String movementType, {DateTime? since}) async {
    final db = await database;
    if (since != null) {
      return await db.query(
        'stock_movements',
        where: 'movement_type = ? AND created_at >= ?',
        whereArgs: [movementType, since.toIso8601String()],
        orderBy: 'created_at DESC',
      );
    }
    return await db.query(
      'stock_movements',
      where: 'movement_type = ?',
      whereArgs: [movementType],
      orderBy: 'created_at DESC',
    );
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
    double? paidAmount,
  }) async {
    try {
    final db = await database;
    final total = (invoiceMap['total'] as num?)?.toDouble() ?? 0.0;
    final invoiceCurrency = (invoiceMap['currency'] as String?) ?? 'YER';
    final now = DateTime.now().toIso8601String();

    // ── التحقق من قفل الفترة المحاسبية ──
    final invoiceDate = invoiceMap['date'] as String? ?? invoiceMap['created_at'] as String? ?? now;
    await _checkFiscalPeriodOpen(invoiceDate);

    // Check if the invoice date falls in a closed fiscal year
    final isClosed = await isDateInClosedPeriod(DateTime.parse(invoiceDate));
    if (isClosed) {
      throw Exception('لا يمكن إضافة فاتورة في سنة مالية مغلقة');
    }

    await db.transaction((txn) async {
      // Insert invoice
      await txn.insert('invoices', invoiceMap);

      // Insert invoice items
      for (final item in items) {
        await txn.insert('invoice_items', item);
      }

      // ── Stock management ──
      // Sale/POS: decrement stock; Purchase: increment stock; Returns do the opposite
      // Also logs stock movements and updates weighted average cost on purchases
      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        // Use base_quantity for stock deduction (always in base unit)
        // Falls back to quantity for backward compat with old invoice items
        final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final invoiceIdStr = invoiceMap['id'] as String? ?? '';
        if (productId == null) continue;

        if (invoiceType == 'sale' || invoiceType == 'pos') {
          if (!isReturn) {
            // Sale: stock leaves warehouse (always in base units)
            // Check if product allows negative stock
            final prodRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            final allowNeg = prodRow.isNotEmpty ? (prodRow.first['allow_negative'] as int?) == 1 : false;
            if (allowNeg) {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            } else {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            }
            // Log stock movement
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'sale',
              'quantity': -baseQuantity,
              'reference_type': invoiceType,
              'reference_id': invoiceIdStr,
              'unit_cost': unitPrice,
              'created_at': now,
            });
          } else {
            // Sale return: stock returns to warehouse (always in base units)
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
              [baseQuantity, now, productId],
            );
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'return',
              'quantity': baseQuantity,
              'reference_type': 'sale_return',
              'reference_id': invoiceIdStr,
              'unit_cost': unitPrice,
              'created_at': now,
            });
          }
        } else if (invoiceType == 'purchase') {
          if (!isReturn) {
            // Purchase: stock enters warehouse (always in base units)
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
              [baseQuantity, now, productId],
            );
            // Update weighted average cost on purchase
            final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isNotEmpty) {
              final currentStock = (productRow.first['current_stock'] as num?)?.toDouble() ?? 0.0;
              final currentAvgCost = (productRow.first['average_cost'] as num?)?.toDouble() ?? 0.0;
              // current_stock already updated above, so subtract the new qty to get the old stock
              final oldStock = currentStock - baseQuantity;
              final newTotalValue = (oldStock * currentAvgCost) + (baseQuantity * unitPrice);
              final newTotalStock = currentStock; // already includes new qty
              final newAvgCost = newTotalStock > 0 ? newTotalValue / newTotalStock : unitPrice;
              await txn.update(
                'products',
                {
                  'average_cost': newAvgCost,
                  'cost_price': newAvgCost,
                  'updated_at': now,
                },
                where: 'id = ?',
                whereArgs: [productId],
              );
            }
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'purchase',
              'quantity': baseQuantity,
              'reference_type': 'purchase',
              'reference_id': invoiceIdStr,
              'unit_cost': unitPrice,
              'created_at': now,
            });
          } else {
            // Purchase return: stock leaves warehouse (always in base units)
            // Check if product allows negative stock
            final prodRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            final allowNeg = prodRow.isNotEmpty ? (prodRow.first['allow_negative'] as int?) == 1 : false;
            if (allowNeg) {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            } else {
              await txn.rawUpdate(
                'UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?',
                [baseQuantity, now, productId],
              );
            }
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'return',
              'quantity': -baseQuantity,
              'reference_type': 'purchase_return',
              'reference_id': invoiceIdStr,
              'unit_cost': unitPrice,
              'created_at': now,
            });
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
      // ── Partial payment handling ──
      // When paidAmount is provided and < total with cash mechanism, create split journal entries:
      // Sale: Debit cash (paid) + Debit customer (remaining) = Credit sales (total)
      // Purchase: Debit purchases (total) = Credit cash (paid) + Credit supplier (remaining)
      final effectivePaid = paidAmount ?? (paymentMechanism == 'credit' ? 0.0 : total);
      final isPartialCash = paymentMechanism == 'cash' && effectivePaid < total - 0.005 && effectivePaid > 0.005;
      final remainingAmount = total - effectivePaid;

      if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
        if (isReturn) {
          // Sale Return: Debit Sales Revenue, Credit Customer/Cash
          final debitAccountId = salesAccountId;
          final creditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;

          if (debitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': debitAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'فاتورة مبيعات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
          }
          if (creditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': creditAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'فاتورة مبيعات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, total, now);
          }
        } else if (isPartialCash) {
          // Sale with partial cash: Debit cash (paid) + Debit customer (remaining), Credit sales (total)
          if (cashBanksAccountId != null && effectivePaid > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': effectivePaid,
              'credit': 0.0,
              'description': 'فاتورة مبيعات (مدفوع) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, cashBanksAccountId, effectivePaid, 0.0, now);
          }
          if (customersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': remainingAmount,
              'credit': 0.0,
              'description': 'فاتورة مبيعات (آجل) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, customersAccountId, remainingAmount, 0.0, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, total, now);
          }
        } else {
          // Normal sale: full cash or full credit
          final debitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          if (debitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': debitAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'فاتورة مبيعات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, total, now);
          }
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        if (isReturn) {
          // Purchase Return: Debit Cash/Supplier, Credit Purchases
          final debitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (debitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': debitAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'فاتورة مشتريات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
          }
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'فاتورة مشتريات - مرتجع - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, total, now);
          }
        } else if (isPartialCash) {
          // Purchase with partial cash: Debit purchases (total), Credit cash (paid) + Credit supplier (remaining)
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, purchasesAccountId, total, 0.0, now);
          }
          if (cashBanksAccountId != null && effectivePaid > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': effectivePaid,
              'description': 'فاتورة مشتريات (مدفوع) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, effectivePaid, now);
          }
          if (suppliersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': remainingAmount,
              'description': 'فاتورة مشتريات (آجل) - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, suppliersAccountId, 0.0, remainingAmount, now);
          }
        } else {
          // Normal purchase: full cash or full credit
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, purchasesAccountId, total, 0.0, now);
          }
          final creditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (creditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': creditAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'فاتورة مشتريات - ${invoiceMap['id']}',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, total, now);
          }
        }
      }

      // ── COGS Journal Entries (تكلفة البضاعة المباعة) ──
      // For sale invoices (not return): Debit COGS, Credit Inventory for average_cost * base_quantity
      // For sale returns: Debit Inventory, Credit COGS
      // For purchase invoices (not return): Debit Inventory, Credit Purchases (transfer to inventory)
      // For purchase returns: Debit Purchases, Credit Inventory (reverse transfer)
      if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
        final cogsAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final cogsAccountId = cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
        final inventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;

        if (cogsAccountId != null && inventoryAccountId != null) {
          double totalCogs = 0.0;
          for (final item in items) {
            final productId = (item['product_id'] as num?)?.toInt();
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
            if (productId == null) continue;

            // Look up product average cost (weighted average)
            final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isEmpty) continue;
            final averageCost = (productRow.first['average_cost'] as num?)?.toDouble()
                          ?? (productRow.first['cost_price'] as num?)?.toDouble() ?? 0.0;
            // COGS must use base_quantity (not quantity) because average_cost is per base unit
            totalCogs += averageCost * baseQuantity;
          }

          if (totalCogs > 0) {
            if (!isReturn) {
              // Sale: Debit COGS, Credit Inventory
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': totalCogs,
                'credit': 0.0,
                'description': 'تكلفة بضاعة مباعة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': 0.0,
                'credit': totalCogs,
                'description': 'تخفيض مخزون - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              // Update account balances
              await _updateAccountBalanceWithJournal(txn, cogsAccountId, totalCogs, 0.0, now);
              await _updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalCogs, now);
            } else {
              // Sale return: Debit Inventory, Credit COGS (reverse)
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': totalCogs,
                'credit': 0.0,
                'description': 'إعادة مخزون مرتجع - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': 0.0,
                'credit': totalCogs,
                'description': 'عكس تكلفة بضاعة مرتجعة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              // Update account balances
              await _updateAccountBalanceWithJournal(txn, inventoryAccountId, totalCogs, 0.0, now);
              await _updateAccountBalanceWithJournal(txn, cogsAccountId, 0.0, totalCogs, now);
            }
          }
        }
      }

      // ── Purchase Inventory Transfer Entries ──
      // In perpetual inventory: Purchases debit Purchases account, but inventory must also increase.
      // Add transfer: Debit Inventory, Credit Purchases (for the cost of items purchased)
      if ((invoiceType == 'purchase' || invoiceType == 'purchase_return')) {
        final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final purchasesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final inventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;
        final purchasesAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;

        if (inventoryAccountId != null && purchasesAccountId != null) {
          double totalPurchaseCost = 0.0;
          for (final item in items) {
            final productId = (item['product_id'] as num?)?.toInt();
            final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 1.0;
            if (productId == null) continue;
            final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isEmpty) continue;
            final averageCost = (productRow.first['average_cost'] as num?)?.toDouble()
                          ?? (productRow.first['cost_price'] as num?)?.toDouble() ?? 0.0;
            totalPurchaseCost += averageCost * baseQuantity;
          }

          if (totalPurchaseCost > 0) {
            if (!isReturn) {
              // Purchase: Debit Inventory (goods come in), Credit Purchases (transfer from purchases account)
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': totalPurchaseCost,
                'credit': 0.0,
                'description': 'إضافة مخزون مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': 0.0,
                'credit': totalPurchaseCost,
                'description': 'تحويل من حساب المشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await _updateAccountBalanceWithJournal(txn, inventoryAccountId, totalPurchaseCost, 0.0, now);
              await _updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, totalPurchaseCost, now);
            } else {
              // Purchase return: Debit Purchases, Credit Inventory (reverse)
              await txn.insert('transactions', {
                'account_id': purchasesAccountId,
                'journal_id': journalId,
                'debit': totalPurchaseCost,
                'credit': 0.0,
                'description': 'عكس تحويل مشتريات مرتجعة - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': 0.0,
                'credit': totalPurchaseCost,
                'description': 'تخفيض مخزون مرتجع مشتريات - ${invoiceMap['id']}',
                'date': now,
                'created_at': now,
              });
              await _updateAccountBalanceWithJournal(txn, purchasesAccountId, totalPurchaseCost, 0.0, now);
              await _updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalPurchaseCost, now);
            }
          }
        }
      }

      // ── Transport Charges ──
      // NOTE: Transport charges are already included in `total` (total = subtotal - discount + tax + transportCharges).
      // The main journal entries and cash box update above already account for transport correctly.
      // No separate transport journal entries are needed here to avoid double-counting.

      // Update customer/supplier balance
      // For full cash payments: entity balance should NOT change (they already paid in full)
      // For partial cash: only the remaining unpaid amount affects entity balance
      // For credit: entity owes the full amount (total already includes transport)
      if (invoiceMap['customer_id'] != null) {
        final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
        double customerAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: entity balance should NOT change (already paid)
          customerAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: only the remaining amount is owed by the customer
          customerAmount = remainingAmount;
        } else {
          // Credit mechanism: entity owes the full amount (total already includes transport)
          customerAmount = total;
        }
        if (isDebit) {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [customerAmount, now, invoiceMap['customer_id']]);
        } else {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [customerAmount, now, invoiceMap['customer_id']]);
        }
      }

      // Supplier balance logic:
      // For full cash payments: entity balance should NOT change (they already paid in full)
      // For partial cash: only the remaining unpaid amount affects entity balance
      // For credit: entity is owed the full amount (total already includes transport)
      if (invoiceMap['supplier_id'] != null) {
        final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
        double supplierAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: entity balance should NOT change (already paid)
          supplierAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: only the remaining amount is owed to the supplier
          supplierAmount = remainingAmount;
        } else {
          // Credit mechanism: entity is owed the full amount (total already includes transport)
          supplierAmount = total;
        }
        if (isCreditToSupplier) {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [supplierAmount, now, invoiceMap['supplier_id']]);
        } else {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [supplierAmount, now, invoiceMap['supplier_id']]);
        }
      }

      // Update cash box balance (total already includes transport charges)
      if (cashBoxId != null) {
        // For partial payments, only update cash box with the paid amount
        final cashAmount = isPartialCash ? effectivePaid : total;
        final isCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn);
        if (isCashIn) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [cashAmount, now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [cashAmount, now, cashBoxId]);
        }
      }
    });
    } catch (e) {
      // If the error is already a closed-fiscal-year message, pass it through
      final msg = e.toString();
      if (msg.contains('سنة مالية مغلقة') || msg.contains('فترة مغلقة')) {
        rethrow;
      }
      // Log the error for audit trail
      await logAuditEvent(
        action: 'error',
        tableName: 'invoices',
        recordId: int.tryParse(invoiceMap['id']?.toString() ?? ''),
        recordType: invoiceType,
        oldValues: 'خطأ أثناء حفظ الفاتورة: $e',
      );
      throw Exception('حدث خطأ أثناء حفظ الفاتورة: $e');
    }
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

  /// Get a single invoice by its ID.
  Future<Map<String, dynamic>?> getInvoiceById(String invoiceId) async {
    final db = await database;
    final results = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all return invoices linked to a specific original invoice.
  Future<List<Map<String, dynamic>>> getLinkedReturns(String invoiceId) async {
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
      WHERE i.original_invoice_id = ?
      ORDER BY i.created_at DESC
    ''', [invoiceId]);
  }

  /// Check return limits for items against their original invoice quantities.
  /// Returns a map of product_id -> error message if any product's total returns exceed its original quantity.
  /// Returns an empty map if all items are within limits.
  Future<Map<int, String>> checkReturnLimits(
    String? originalInvoiceId,
    List<Map<String, dynamic>> items,
  ) async {
    if (originalInvoiceId == null || originalInvoiceId.isEmpty) return {};

    final db = await database;
    final errors = <int, String>{};

    // Get original invoice items
    final originalItems = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [originalInvoiceId],
    );

    // Build a map of product_id -> original quantity
    final originalQtyMap = <int, double>{};
    for (final item in originalItems) {
      final productId = (item['product_id'] as num?)?.toInt() ?? 0;
      final qty = (item['base_quantity'] as num?)?.toDouble() ??
                  (item['quantity'] as num?)?.toDouble() ?? 0.0;
      originalQtyMap[productId] = (originalQtyMap[productId] ?? 0.0) + qty;
    }

    // Get existing returns for this original invoice (excluding cancelled)
    final existingReturns = await db.rawQuery('''
      SELECT ii.product_id, SUM(ii.base_quantity) AS total_returned
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.original_invoice_id = ? AND i.status != 'cancelled'
      GROUP BY ii.product_id
    ''', [originalInvoiceId]);

    // Build map of product_id -> already returned quantity
    final alreadyReturnedMap = <int, double>{};
    for (final row in existingReturns) {
      final productId = (row['product_id'] as num?)?.toInt() ?? 0;
      final totalReturned = (row['total_returned'] as num?)?.toDouble() ?? 0.0;
      alreadyReturnedMap[productId] = totalReturned;
    }

    // Check each item in the new return
    for (final item in items) {
      final productId = (item['product_id'] as num?)?.toInt() ?? 0;
      if (productId == 0) continue;
      final productName = item['product_name'] as String? ?? '';
      final newReturnQty = (item['base_quantity'] as num?)?.toDouble() ??
                           (item['quantity'] as num?)?.toDouble() ?? 0.0;

      final originalQty = originalQtyMap[productId] ?? 0.0;
      if (originalQty == 0.0) {
        errors[productId] = 'الصنف "$productName" غير موجود في الفاتورة الأصلية';
        continue;
      }

      final alreadyReturned = alreadyReturnedMap[productId] ?? 0.0;
      final totalAfterReturn = alreadyReturned + newReturnQty;

      if (totalAfterReturn > originalQty + 0.005) {
        final remaining = originalQty - alreadyReturned;
        errors[productId] = 'كمية المرتجع للصنف "$productName" ($totalAfterReturn) تتجاوز الكمية المسموحة ($remaining متبقي من أصل $originalQty)';
      }
    }

    return errors;
  }

  /// Soft-delete an invoice by setting status to 'cancelled'.
  /// Does NOT reverse journal entries — use [cancelInvoice] for full reversal.
  Future<int> deleteInvoice(String id) async {
    final db = await database;
    return await db.update('invoices', {'status': 'cancelled'}, where: 'id = ?', whereArgs: [id]);
  }

  /// Record a payment against an existing invoice.
  /// Updates invoice paid_amount/remaining/status, creates journal entries,
  /// updates customer/supplier balance, and updates cash box balance.
  Future<void> recordInvoicePayment({
    required String invoiceId,
    required double amount,
    required int cashBoxId,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // 1. Get the invoice
    final invoiceRows = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceRows.isEmpty) return;
    final invoice = invoiceRows.first;

    final currentRemaining = (invoice['remaining'] as num?)?.toDouble() ?? 0.0;
    final currentPaid = (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
    final invoiceCurrency = (invoice['currency'] as String?) ?? 'YER';
    final invoiceType = (invoice['type'] as String?) ?? 'sale';
    final customerId = invoice['customer_id'] as int?;
    final supplierId = invoice['supplier_id'] as int?;

    // 2. Validate amount doesn't exceed remaining
    if (amount <= 0) return;
    final paymentAmount = amount > currentRemaining ? currentRemaining : amount;
    final newPaid = currentPaid + paymentAmount;
    final newRemaining = total - newPaid;

    // 3. Determine new status
    String newStatus;
    if (newRemaining <= 0.005) {
      newStatus = 'paid';
    } else if (newPaid > 0) {
      newStatus = 'partial';
    } else {
      newStatus = 'unpaid';
    }

    await db.transaction((txn) async {
      // 4. Update invoice paid_amount, remaining, status
      await txn.update(
        'invoices',
        {
          'paid_amount': newPaid,
          'remaining': newRemaining > 0 ? newRemaining : 0.0,
          'status': newStatus,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      // 5. Create journal entries
      final journalId = DateTime.now().millisecondsSinceEpoch;
      final codeOffset = invoiceCurrency == 'SAR' ? 1 : (invoiceCurrency == 'USD' ? 2 : 0);

      final cashBanksAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1100 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final customersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1200 + codeOffset).toString(), invoiceCurrency], limit: 1);
      final suppliersAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(2100 + codeOffset).toString(), invoiceCurrency], limit: 1);

      final cashBanksAccountId = cashBanksAccount.isNotEmpty ? cashBanksAccount.first['id'] as int : null;
      final customersAccountId = customersAccount.isNotEmpty ? customersAccount.first['id'] as int : null;
      final suppliersAccountId = suppliersAccount.isNotEmpty ? suppliersAccount.first['id'] as int : null;

      // For sale invoices: Debit cash, Credit customer (customer owes less)
      // For purchase invoices: Debit supplier, Credit cash (we owe supplier less)
      if (invoiceType == 'sale' || invoiceType == 'sale_return') {
        // Sale: customer is paying us → Debit cash, Credit customer account
        if (cashBanksAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBanksAccountId,
            'journal_id': journalId,
            'debit': paymentAmount,
            'credit': 0.0,
            'description': 'تحصيل دفعة فاتورة مبيعات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, cashBanksAccountId, paymentAmount, 0.0, now);
        }
        if (customersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': customersAccountId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': paymentAmount,
            'description': 'تحصيل دفعة فاتورة مبيعات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, paymentAmount, now);
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        // Purchase: we are paying supplier → Debit supplier, Credit cash
        if (suppliersAccountId != null) {
          await txn.insert('transactions', {
            'account_id': suppliersAccountId,
            'journal_id': journalId,
            'debit': paymentAmount,
            'credit': 0.0,
            'description': 'سداد دفعة فاتورة مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, suppliersAccountId, paymentAmount, 0.0, now);
        }
        if (cashBanksAccountId != null) {
          await txn.insert('transactions', {
            'account_id': cashBanksAccountId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': paymentAmount,
            'description': 'سداد دفعة فاتورة مشتريات - $invoiceId',
            'date': now,
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, paymentAmount, now);
        }
      }

      // 6. Update customer balance (customer owes less after payment)
      if (customerId != null) {
        await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [paymentAmount, now, customerId]);
      }

      // 7. Update supplier balance (we owe less after payment)
      if (supplierId != null) {
        await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [paymentAmount, now, supplierId]);
      }

      // 8. Update cash box balance
      if (invoiceType == 'sale' || invoiceType == 'sale_return') {
        // Sale: cash comes in
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [paymentAmount, now, cashBoxId]);
      } else {
        // Purchase: cash goes out
        await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [paymentAmount, now, cashBoxId]);
      }
    });
  }

  /// Cancel an invoice: soft-delete + reversal journal entries + balance reversals + stock restore.
  Future<void> cancelInvoice(String id) async {
    try {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Fetch invoice
    final invoiceRows = await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
    if (invoiceRows.isEmpty) return;
    final invoice = invoiceRows.first;

    // Already cancelled — nothing to do
    if ((invoice['status'] as String?) == 'cancelled') return;

    // Check if the invoice date falls in a closed fiscal year
    final invoiceDate = invoice['date'] as String? ?? invoice['created_at'] as String;
    final isClosed = await isDateInClosedPeriod(DateTime.parse(invoiceDate));
    if (isClosed) {
      throw Exception('لا يمكن إلغاء فاتورة في سنة مالية مغلقة');
    }

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

      // Determine original debit/credit accounts and handle partial payments
      // Check for partial payment (same logic as saveInvoiceWithJournalEntries)
      final paidAmount = (invoice['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final remainingAmount = (invoice['remaining'] as num?)?.toDouble() ?? 0.0;
      final isPartialCash = paymentMechanism == 'cash' && paidAmount > 0.005 && remainingAmount > 0.005;

      if (invoiceType == 'sale' || invoiceType == 'sale_return' || invoiceType == 'pos') {
        if (isPartialCash && !isReturn) {
          // Reverse partial cash sale: Credit Cash (paid), Credit Customer (remaining), Debit Sales (total)
          if (cashBanksAccountId != null && paidAmount > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': paidAmount,
              'description': 'إلغاء فاتورة مبيعات (مدفوع) - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, cashBanksAccountId, 0.0, paidAmount, now);
          }
          if (customersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': customersAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': remainingAmount,
              'description': 'إلغاء فاتورة مبيعات (آجل) - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, customersAccountId, 0.0, remainingAmount, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مبيعات - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, salesAccountId, total, 0.0, now);
          }
        } else if (isReturn) {
          // Reverse sale return: Debit Customer/Cash (original credit), Credit Sales (original debit)
          final originalCreditAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          if (originalCreditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalCreditAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مبيعات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, originalCreditAccountId, total, 0.0, now);
          }
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'إلغاء فاتورة مبيعات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, salesAccountId, 0.0, total, now);
          }
        } else {
          // Normal reversal (full cash or full credit): swap debit/credit
          final originalDebitAccountId = paymentMechanism == 'credit' ? customersAccountId : cashBanksAccountId;
          if (salesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': salesAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مبيعات - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, salesAccountId, total, 0.0, now);
          }
          if (originalDebitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalDebitAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'إلغاء فاتورة مبيعات - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, originalDebitAccountId, 0.0, total, now);
          }
        }
      } else if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
        if (isPartialCash && !isReturn) {
          // Reverse partial cash purchase: Debit Cash (paid), Debit Supplier (remaining), Credit Purchases (total)
          if (cashBanksAccountId != null && paidAmount > 0) {
            await txn.insert('transactions', {
              'account_id': cashBanksAccountId,
              'journal_id': journalId,
              'debit': paidAmount,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مشتريات (مدفوع) - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, cashBanksAccountId, paidAmount, 0.0, now);
          }
          if (suppliersAccountId != null && remainingAmount > 0) {
            await txn.insert('transactions', {
              'account_id': suppliersAccountId,
              'journal_id': journalId,
              'debit': remainingAmount,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مشتريات (آجل) - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, suppliersAccountId, remainingAmount, 0.0, now);
          }
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'إلغاء فاتورة مشتريات - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, total, now);
          }
        } else if (isReturn) {
          // Reverse purchase return: Debit Purchases (original credit), Credit Cash/Supplier (original debit)
          final originalDebitAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مشتريات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, purchasesAccountId, total, 0.0, now);
          }
          if (originalDebitAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalDebitAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'إلغاء فاتورة مشتريات - مرتجع - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, originalDebitAccountId, 0.0, total, now);
          }
        } else {
          // Normal reversal (full cash or full credit): swap debit/credit
          final originalCreditAccountId = paymentMechanism == 'credit' ? suppliersAccountId : cashBanksAccountId;
          if (originalCreditAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': originalCreditAccountId,
              'journal_id': journalId,
              'debit': total,
              'credit': 0.0,
              'description': 'إلغاء فاتورة مشتريات - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, originalCreditAccountId, total, 0.0, now);
          }
          if (purchasesAccountId != null && total > 0) {
            await txn.insert('transactions', {
              'account_id': purchasesAccountId,
              'journal_id': journalId,
              'debit': 0.0,
              'credit': total,
              'description': 'إلغاء فاتورة مشتريات - $id',
              'date': now,
              'created_at': now,
            });
            await _updateAccountBalanceWithJournal(txn, purchasesAccountId, 0.0, total, now);
          }
        }
      }

      // 2b. Reverse COGS journal entries (for sale invoices)
      if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
        final cogsAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
        final cogsAccountId = cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
        final inventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;

        if (cogsAccountId != null && inventoryAccountId != null) {
          double totalCogs = 0.0;
          for (final item in items) {
            final productId = (item['product_id'] as num?)?.toInt();
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
            if (productId == null) continue;

            final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
            if (productRow.isEmpty) continue;
            final costPrice = (productRow.first['cost_price'] as num?)?.toDouble() ?? 0.0;
            totalCogs += costPrice * quantity;
          }

          if (totalCogs > 0) {
            if (!isReturn) {
              // Original: Debit COGS, Credit Inventory → Reverse: Debit Inventory, Credit COGS
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': totalCogs,
                'credit': 0.0,
                'description': 'إلغاء تكلفة بضاعة مباعة - $id',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': 0.0,
                'credit': totalCogs,
                'description': 'إلغاء تخفيض مخزون - $id',
                'date': now,
                'created_at': now,
              });
              await _updateAccountBalanceWithJournal(txn, inventoryAccountId, totalCogs, 0.0, now);
              await _updateAccountBalanceWithJournal(txn, cogsAccountId, 0.0, totalCogs, now);
            } else {
              // Original return: Debit Inventory, Credit COGS → Reverse: Debit COGS, Credit Inventory
              await txn.insert('transactions', {
                'account_id': cogsAccountId,
                'journal_id': journalId,
                'debit': totalCogs,
                'credit': 0.0,
                'description': 'إلغاء إعادة مخزون مرتجع - $id',
                'date': now,
                'created_at': now,
              });
              await txn.insert('transactions', {
                'account_id': inventoryAccountId,
                'journal_id': journalId,
                'debit': 0.0,
                'credit': totalCogs,
                'description': 'إلغاء عكس تكلفة بضاعة مرتجعة - $id',
                'date': now,
                'created_at': now,
              });
              await _updateAccountBalanceWithJournal(txn, cogsAccountId, totalCogs, 0.0, now);
              await _updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalCogs, now);
            }
          }
        }
      }

      // 3. Transport charges reversal
      // NOTE: Transport charges are already included in `total`, so the main reversal entries above
      // already handle transport correctly. No separate transport reversal is needed.

      // 4. Reverse customer/supplier balance
      // Must mirror the save logic: full cash = no balance change, partial cash = only remaining, credit = total
      if (invoice['customer_id'] != null) {
        final wasDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
        double customerReversalAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: original save set customerAmount = 0, so reversal is also 0
          customerReversalAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: original save set customerAmount = remainingAmount
          customerReversalAmount = remainingAmount;
        } else {
          // Credit mechanism: original save set customerAmount = total (already includes transport)
          customerReversalAmount = total;
        }
        if (wasDebit) {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [customerReversalAmount, now, invoice['customer_id']]);
        } else {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [customerReversalAmount, now, invoice['customer_id']]);
        }
      }

      if (invoice['supplier_id'] != null) {
        final wasCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
        double supplierReversalAmount;
        if (paymentMechanism == 'cash' && !isPartialCash) {
          // Full cash payment: original save set supplierAmount = 0, so reversal is also 0
          supplierReversalAmount = 0;
        } else if (isPartialCash && !isReturn) {
          // Partial cash: original save set supplierAmount = remainingAmount
          supplierReversalAmount = remainingAmount;
        } else {
          // Credit mechanism: original save set supplierAmount = total (already includes transport)
          supplierReversalAmount = total;
        }
        if (wasCreditToSupplier) {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [supplierReversalAmount, now, invoice['supplier_id']]);
        } else {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [supplierReversalAmount, now, invoice['supplier_id']]);
        }
      }

      // 5. Reverse cash box balance
      // Must mirror the save logic: full cash = reverse total, partial cash = reverse paidAmount only
      if (cashBoxId != null) {
        final cashReversalAmount = isPartialCash ? paidAmount : total;
        final wasCashIn = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'purchase' && isReturn) || (invoiceType == 'pos' && !isReturn);
        if (wasCashIn) {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance - ?, updated_at = ? WHERE id = ?', [cashReversalAmount, now, cashBoxId]);
        } else {
          await txn.rawUpdate('UPDATE cash_boxes SET balance = balance + ?, updated_at = ? WHERE id = ?', [cashReversalAmount, now, cashBoxId]);
        }
        // No separate transport reversal needed - transport is already included in total/paidAmount
      }

      // 6. Restore product stock
      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        if (productId == null) continue;
        // Check allow_negative for this product
        final prodRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        final allowNeg = prodRow.isNotEmpty ? (prodRow.first['allow_negative'] as int?) == 1 : false;

        if (invoiceType == 'sale' || invoiceType == 'pos') {
          if (!isReturn) {
            // Was decremented, now restore
            await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
          } else {
            // Was incremented (return), now decrement
            if (allowNeg) {
              await txn.rawUpdate('UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
            } else {
              await txn.rawUpdate('UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?', [quantity, now, productId]);
            }
          }
        } else if (invoiceType == 'purchase') {
          if (!isReturn) {
            // Was incremented, now decrement
            if (allowNeg) {
              await txn.rawUpdate('UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
            } else {
              await txn.rawUpdate('UPDATE products SET current_stock = MAX(current_stock - ?, 0), updated_at = ? WHERE id = ?', [quantity, now, productId]);
            }
          } else {
            // Was decremented (return), now restore
            await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?', [quantity, now, productId]);
          }
        }
      }
    });

    // Log audit event for invoice cancellation
    await logAuditEvent(
      action: 'cancel',
      tableName: 'invoices',
      recordId: int.tryParse(id),
      recordType: invoice['type'] as String?,
      oldValues: jsonEncode({'status': invoice['status']}),
      newValues: jsonEncode({'status': 'cancelled'}),
      userName: null,
    );
    } catch (e) {
      // If the error is already a closed-fiscal-year message, pass it through
      final msg = e.toString();
      if (msg.contains('سنة مالية مغلقة') || msg.contains('فترة مغلقة')) {
        rethrow;
      }
      // Log the error for audit trail
      await logAuditEvent(
        action: 'error',
        tableName: 'invoices',
        recordId: int.tryParse(id),
        oldValues: 'خطأ أثناء إلغاء الفاتورة: $e',
      );
      throw Exception('حدث خطأ أثناء إلغاء الفاتورة: $e');
    }
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
          await _updateAccountBalanceWithJournal(txn, expenseAccId, amountBase, 0.0, now);
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
          await _updateAccountBalanceWithJournal(txn, cashAccountId, 0.0, amountBase, now);
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
          await _updateAccountBalanceWithJournal(txn, cashAccountId, amountBase, 0.0, now);
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
          await _updateAccountBalanceWithJournal(txn, expenseAccId, 0.0, amountBase, now);
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

    // Get the account's balance_type to compute balance correctly
    final accountRow = await db.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (accountRow.isEmpty) return;
    final balanceType = accountRow.first['balance_type'] as String? ?? 'credit';

    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(debit) - SUM(credit), 0.0) AS net_debit, COALESCE(SUM(credit) - SUM(debit), 0.0) AS net_credit FROM transactions WHERE account_id = ?',
      [accountId],
    );
    final netDebit = (result.first['net_debit'] as num?)?.toDouble() ?? 0.0;
    final netCredit = (result.first['net_credit'] as num?)?.toDouble() ?? 0.0;

    // For debit-balance accounts (ASSET, COST): balance = debit - credit
    // For credit-balance accounts (LIABILITY, REVENUE, EXPENSE): balance = credit - debit
    final computedBalance = (balanceType == 'debit') ? netDebit : netCredit;
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

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
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
        await _updateAccountBalanceWithJournal(txn, toCashBanksAccountId, toAmount, 0.0, now);
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
        await _updateAccountBalanceWithJournal(txn, fromCashBanksAccountId, 0.0, fromAmount, now);
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
            await _updateAccountBalanceWithJournal(txn, gainAccountId, 0.0, gainLoss, now);
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
            await _updateAccountBalanceWithJournal(txn, lossAccountId, gainLoss, 0.0, now);
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
        await _updateAccountBalanceWithJournal(txn, toAccountId, amount, 0.0, now);
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
        await _updateAccountBalanceWithJournal(txn, fromAccountId, 0.0, amount, now);
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
          await _updateAccountBalanceWithJournal(txn, debitAccountId, total, 0.0, now);
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
          await _updateAccountBalanceWithJournal(txn, creditAccountId, 0.0, total, now);
        }

        // ── COGS Journal Entries (تكلفة البضاعة المباعة) ──
        if ((invoiceType == 'sale' || invoiceType == 'pos' || invoiceType == 'sale_return')) {
          final cogsAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3200 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final cogsAccountId = cogsAccount.isNotEmpty ? cogsAccount.first['id'] as int : null;
          final inventoryAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;

          if (cogsAccountId != null && inventoryAccountId != null) {
            // Fetch invoice items to calculate COGS
            final invoiceItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
            double totalCogs = 0.0;
            for (final item in invoiceItems) {
              final productId = (item['product_id'] as num?)?.toInt();
              final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
              final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? quantity;
              if (productId == null) continue;

              final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
              if (productRow.isEmpty) continue;
              final averageCost = (productRow.first['average_cost'] as num?)?.toDouble()
                            ?? (productRow.first['cost_price'] as num?)?.toDouble() ?? 0.0;
              // COGS must use base_quantity (not quantity) because average_cost is per base unit
              totalCogs += averageCost * baseQuantity;
            }

            if (totalCogs > 0) {
              if (!isReturn) {
                await txn.insert('transactions', {
                  'account_id': cogsAccountId,
                  'journal_id': journalId,
                  'debit': totalCogs,
                  'credit': 0.0,
                  'description': 'تكلفة بضاعة مباعة - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': inventoryAccountId,
                  'journal_id': journalId,
                  'debit': 0.0,
                  'credit': totalCogs,
                  'description': 'تخفيض مخزون - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _updateAccountBalanceWithJournal(txn, cogsAccountId, totalCogs, 0.0, now);
                await _updateAccountBalanceWithJournal(txn, inventoryAccountId, 0.0, totalCogs, now);
              } else {
                await txn.insert('transactions', {
                  'account_id': inventoryAccountId,
                  'journal_id': journalId,
                  'debit': totalCogs,
                  'credit': 0.0,
                  'description': 'إعادة مخزون مرتجع - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': cogsAccountId,
                  'journal_id': journalId,
                  'debit': 0.0,
                  'credit': totalCogs,
                  'description': 'عكس تكلفة بضاعة مرتجعة - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _updateAccountBalanceWithJournal(txn, inventoryAccountId, totalCogs, 0.0, now);
                await _updateAccountBalanceWithJournal(txn, cogsAccountId, 0.0, totalCogs, now);
              }
            }
          }
        }

        // ── Purchase Inventory Transfer Entries ──
        if ((invoiceType == 'purchase' || invoiceType == 'purchase_return')) {
          final inventoryAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(1300 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final purchasesAccount = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [(3100 + codeOffset).toString(), invoiceCurrency], limit: 1);
          final invAccountId = inventoryAccount.isNotEmpty ? inventoryAccount.first['id'] as int : null;
          final purchAccountId = purchasesAccount.isNotEmpty ? purchasesAccount.first['id'] as int : null;

          if (invAccountId != null && purchAccountId != null) {
            final invoiceItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
            double totalPurchaseCost = 0.0;
            for (final item in invoiceItems) {
              final productId = (item['product_id'] as num?)?.toInt();
              final baseQuantity = (item['base_quantity'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 1.0;
              if (productId == null) continue;
              final productRow = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
              if (productRow.isEmpty) continue;
              final avgCost = (productRow.first['average_cost'] as num?)?.toDouble()
                          ?? (productRow.first['cost_price'] as num?)?.toDouble() ?? 0.0;
              totalPurchaseCost += avgCost * baseQuantity;
            }

            if (totalPurchaseCost > 0) {
              if (!isReturn) {
                await txn.insert('transactions', {
                  'account_id': invAccountId,
                  'journal_id': journalId,
                  'debit': totalPurchaseCost,
                  'credit': 0.0,
                  'description': 'إضافة مخزون مشتريات - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': purchAccountId,
                  'journal_id': journalId,
                  'debit': 0.0,
                  'credit': totalPurchaseCost,
                  'description': 'تحويل من حساب المشتريات - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _updateAccountBalanceWithJournal(txn, invAccountId, totalPurchaseCost, 0.0, now);
                await _updateAccountBalanceWithJournal(txn, purchAccountId, 0.0, totalPurchaseCost, now);
              } else {
                await txn.insert('transactions', {
                  'account_id': purchAccountId,
                  'journal_id': journalId,
                  'debit': totalPurchaseCost,
                  'credit': 0.0,
                  'description': 'عكس تحويل مشتريات مرتجعة - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await txn.insert('transactions', {
                  'account_id': invAccountId,
                  'journal_id': journalId,
                  'debit': 0.0,
                  'credit': totalPurchaseCost,
                  'description': 'تخفيض مخزون مرتجع مشتريات - $invoiceId',
                  'date': now,
                  'created_at': now,
                });
                await _updateAccountBalanceWithJournal(txn, purchAccountId, totalPurchaseCost, 0.0, now);
                await _updateAccountBalanceWithJournal(txn, invAccountId, 0.0, totalPurchaseCost, now);
              }
            }
          }
        }

        // ── Transport Charges ──
        // NOTE: Transport charges are already included in `total` (total = subtotal - discount + tax + transportCharges).
        // The main journal entries and cash box update above already account for transport correctly.
        // No separate transport journal entries are needed here to avoid double-counting.

        // تحديث رصيد العميل/المورد
        // NOTE: `total` already includes transport charges, so no need to add them again
        if (invoice['customer_id'] != null) {
          final isDebit = (invoiceType == 'sale' && !isReturn) || (invoiceType == 'pos' && !isReturn) || (invoiceType == 'sale_return' && isReturn);
          // For credit payments, customer owes the full total (already includes transport)
          // For cash payments, customer balance should not change (they paid)
          final customerAmount = paymentMechanism == 'credit' ? total : 0.0;
          if (isDebit) {
            await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [customerAmount, now, invoice['customer_id']]);
          } else {
            await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [customerAmount, now, invoice['customer_id']]);
          }
        }

        if (invoice['supplier_id'] != null) {
          final isCreditToSupplier = (invoiceType == 'purchase' && !isReturn) || (invoiceType == 'purchase_return' && isReturn);
          // For credit purchases, supplier is owed the full total (already includes transport)
          // For cash purchases, supplier balance should not change (we paid)
          final supplierAmount = paymentMechanism == 'credit' ? total : 0.0;
          if (isCreditToSupplier) {
            await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [supplierAmount, now, invoice['supplier_id']]);
          } else {
            await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [supplierAmount, now, invoice['supplier_id']]);
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
  // ══════════════════════════════════════════════════════════════
  //  Voucher (السندات) CRUD methods - v18
  // ══════════════════════════════════════════════════════════════

  /// إدراج سند مع بنوده وإنشاء قيود يومية
  /// يتضمن التحقق الإلزامي من توازن القيد المزدوج
  Future<int> insertVoucher(Map<String, dynamic> voucherMap, List<Map<String, dynamic>> items) async {
    // ── التحقق من توازن القيد: مجموع المدين يجب أن يساوي مجموع الدائن ──
    final totalDebit = items.fold(0.0, (sum, item) => sum + ((item['debit'] as num?)?.toDouble() ?? 0.0));
    final totalCredit = items.fold(0.0, (sum, item) => sum + ((item['credit'] as num?)?.toDouble() ?? 0.0));
    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception('القيد غير متوازن: المدين = $totalDebit، الدائن = $totalCredit');
    }

    // ── التحقق من قفل الفترة المحاسبية ──
    final voucherDate = voucherMap['date'] as String? ?? DateTime.now().toIso8601String();
    await _checkFiscalPeriodOpen(voucherDate);

    final db = await database;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    int voucherId = 0;
    await db.transaction((txn) async {
      // إدراج السند
      voucherId = await txn.insert('vouchers', voucherMap);

      // إدراج بنود السند وإنشاء قيود يومية
      for (final item in items) {
        final itemMap = Map<String, dynamic>.from(item);
        itemMap['voucher_id'] = voucherId;
        itemMap['created_at'] = now;
        await txn.insert('voucher_items', itemMap);

        // إنشاء قيد يومي لكل بند
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (item['credit'] as num?)?.toDouble() ?? 0.0;
        if (accountId != null && (debit > 0 || credit > 0)) {
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': journalId,
            'debit': debit,
            'credit': credit,
            'description': item['description'] ?? voucherMap['description'] ?? 'سند ${voucherMap['voucher_number']}',
            'date': voucherMap['date'],
            'created_at': now,
          });

          // تحديث رصيد الحساب باستخدام منطق balance_type
          await _updateAccountBalanceWithJournal(txn, accountId, debit, credit, now);
        }
      }

      // تحديث رصيد الصندوق إذا كان مرتبطاً بالسند
      final cashBoxId = voucherMap['cash_box_id'];
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance = (cashBox.first['balance'] as num?)?.toDouble() ?? 0.0;
          final totalAmount = (voucherMap['total_amount'] as num?)?.toDouble() ?? 0.0;
          final voucherType = voucherMap['voucher_type'] as String? ?? 'receipt';
          double newCashBalance;
          if (voucherType == 'receipt') {
            newCashBalance = currentBalance + totalAmount;
          } else if (voucherType == 'payment') {
            newCashBalance = currentBalance - totalAmount;
          } else {
            newCashBalance = currentBalance;
          }
          await txn.update('cash_boxes', {'balance': newCashBalance, 'updated_at': now}, where: 'id = ?', whereArgs: [cashBoxId]);
        }
      }

      // تحديث رصيد العميل/المورد إذا كان مرتبطاً بالسند
      final customerId = voucherMap['customer_id'];
      final supplierId = voucherMap['supplier_id'];
      final totalAmount = (voucherMap['total_amount'] as num?)?.toDouble() ?? 0.0;
      final voucherType = voucherMap['voucher_type'] as String? ?? 'receipt';

      if (customerId != null && totalAmount > 0) {
        // Receipt voucher for customer: customer pays us → decrease customer balance
        // Payment voucher to customer: we pay customer → increase customer balance
        if (voucherType == 'receipt') {
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalAmount, now, customerId]);
        } else if (voucherType == 'payment') {
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalAmount, now, customerId]);
        }
      }

      if (supplierId != null && totalAmount > 0) {
        // Payment voucher for supplier: we pay supplier → decrease supplier balance
        // Receipt voucher from supplier: supplier pays us → increase supplier balance
        if (voucherType == 'payment') {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalAmount, now, supplierId]);
        } else if (voucherType == 'receipt') {
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalAmount, now, supplierId]);
        }
      }
    });
    return voucherId;
  }

  /// جلب جميع السندات مع فلتر اختياري حسب النوع
  Future<List<Map<String, dynamic>>> getAllVouchers({String? type, String orderBy = 'created_at DESC'}) async {
    final db = await database;
    if (type != null) {
      return await db.query('vouchers', where: 'voucher_type = ?', whereArgs: [type], orderBy: orderBy);
    }
    return await db.query('vouchers', orderBy: orderBy);
  }

  /// جلب بنود سند معين
  Future<List<Map<String, dynamic>>> getVoucherItems(int voucherId) async {
    final db = await database;
    return await db.query('voucher_items', where: 'voucher_id = ?', whereArgs: [voucherId]);
  }

  /// حذف سند وعكس القيود اليومية
  Future<int> deleteVoucher(int voucherId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // جلب بيانات السند
      final voucher = await txn.query('vouchers', where: 'id = ?', whereArgs: [voucherId], limit: 1);
      if (voucher.isEmpty) return;

      final voucherData = voucher.first;
      final voucherDate = voucherData['date'] as String? ?? now;
      final voucherNumber = voucherData['voucher_number'] as String? ?? '';
      final voucherType = voucherData['voucher_type'] as String? ?? '';
      final totalAmount = (voucherData['total_amount'] as num?)?.toDouble() ?? 0.0;
      final cashBoxId = voucherData['cash_box_id'];

      // جلب بنود السند وعكس القيود
      final items = await txn.query('voucher_items', where: 'voucher_id = ?', whereArgs: [voucherId]);
      for (final item in items) {
        final accountId = (item['account_id'] as num?)?.toInt();
        final debit = (item['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (item['credit'] as num?)?.toDouble() ?? 0.0;
        if (accountId != null && (debit > 0 || credit > 0)) {
          // عكس القيد:debit يصبح credit والعكس
          await txn.insert('transactions', {
            'account_id': accountId,
            'journal_id': DateTime.now().millisecondsSinceEpoch,
            'debit': credit,
            'credit': debit,
            'description': 'عكس سند $voucherNumber',
            'date': voucherDate,
            'created_at': now,
          });

          // تحديث رصيد الحساب (عكس) باستخدام منطق balance_type
          await _updateAccountBalanceWithJournal(txn, accountId, credit, debit, now);
        }
      }

      // عكس تأثير الصندوق
      if (cashBoxId != null) {
        final cashBox = await txn.query('cash_boxes', where: 'id = ?', whereArgs: [cashBoxId], limit: 1);
        if (cashBox.isNotEmpty) {
          final currentBalance = (cashBox.first['balance'] as num?)?.toDouble() ?? 0.0;
          double newCashBalance;
          if (voucherType == 'receipt') {
            newCashBalance = currentBalance - totalAmount;
          } else if (voucherType == 'payment') {
            newCashBalance = currentBalance + totalAmount;
          } else {
            newCashBalance = currentBalance;
          }
          await txn.update('cash_boxes', {'balance': newCashBalance, 'updated_at': now}, where: 'id = ?', whereArgs: [cashBoxId]);
        }
      }

      // عكس تأثير رصيد العميل/المورد
      final customerId = voucherData['customer_id'];
      final supplierId = voucherData['supplier_id'];
      if (customerId != null && totalAmount > 0) {
        if (voucherType == 'receipt') {
          // Original receipt decreased customer balance, so reverse increases it
          await txn.rawUpdate('UPDATE customers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalAmount, now, customerId]);
        } else if (voucherType == 'payment') {
          // Original payment increased customer balance, so reverse decreases it
          await txn.rawUpdate('UPDATE customers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalAmount, now, customerId]);
        }
      }
      if (supplierId != null && totalAmount > 0) {
        if (voucherType == 'payment') {
          // Original payment decreased supplier balance, so reverse increases it
          await txn.rawUpdate('UPDATE suppliers SET balance = balance + ?, updated_at = ? WHERE id = ?', [totalAmount, now, supplierId]);
        } else if (voucherType == 'receipt') {
          // Original receipt increased supplier balance, so reverse decreases it
          await txn.rawUpdate('UPDATE suppliers SET balance = balance - ?, updated_at = ? WHERE id = ?', [totalAmount, now, supplierId]);
        }
      }

      // حذف بنود السند ثم السند نفسه
      await txn.delete('voucher_items', where: 'voucher_id = ?', whereArgs: [voucherId]);
      await txn.delete('vouchers', where: 'id = ?', whereArgs: [voucherId]);
    });
    return 1;
  }

  /// جلب سند برقمه
  Future<Map<String, dynamic>?> getVoucherByNumber(String number) async {
    final db = await database;
    final result = await db.query('vouchers', where: 'voucher_number = ?', whereArgs: [number], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  /// توليد رقم السند التالي حسب النوع
  Future<String> getNextVoucherNumber(String type) async {
    final db = await database;
    final year = DateTime.now().year.toString();
    final prefixMap = {
      'receipt': 'REC',
      'payment': 'PAY',
      'settlement': 'SET',
      'compound': 'CMP',
      'inventory': 'INV',
    };
    final prefix = prefixMap[type] ?? 'VCH';
    final fullPrefix = '$prefix-$year-';

    final result = await db.rawQuery(
      "SELECT voucher_number FROM vouchers WHERE voucher_number LIKE ? ORDER BY id DESC LIMIT 1",
      ['$fullPrefix%'],
    );

    if (result.isEmpty) {
      return '$fullPrefix${1.toString().padLeft(3, '0')}';
    }

    final lastNumber = result.first['voucher_number'] as String;
    final parts = lastNumber.split('-');
    if (parts.length >= 3) {
      final lastSeq = int.tryParse(parts.last) ?? 0;
      return '$fullPrefix${(lastSeq + 1).toString().padLeft(3, '0')}';
    }
    return '$fullPrefix${1.toString().padLeft(3, '0')}';
  }

  Future<int> getTodayPosInvoiceCount(String datePrefix) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices WHERE id LIKE ?",
      ['POS-$datePrefix%'],
    );
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  // ══════════════════════════════════════════════════════════════
  //  العمليات اليومية والتقارير الإضافية
  //  Daily Operations & Additional Reports
  // ══════════════════════════════════════════════════════════════

  /// جلب العمليات اليومية المجمعة لتاريخ محدد
  /// Returns combined list of all daily transactions for a specific date.
  Future<List<Map<String, dynamic>>> getDailyOperations(DateTime date) async {
    final db = await database;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final startStr = dayStart.toIso8601String();
    final endStr = dayEnd.toIso8601String();

    final List<Map<String, dynamic>> operations = [];

    // فواتير المبيعات
    final saleInvoices = await db.rawQuery(
      "SELECT i.id, i.type, i.total, i.created_at, i.currency, "
      "CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل') "
      "ELSE 'بدون عميل' END AS entity_name "
      "FROM invoices i LEFT JOIN customers c ON i.customer_id = c.id "
      "WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 "
      "AND i.created_at >= ? AND i.created_at < ? "
      "ORDER BY i.created_at DESC",
      [startStr, endStr],
    );
    for (final row in saleInvoices) {
      operations.add({
        'type': 'sale_invoice',
        'type_label': 'فاتورة مبيعات',
        'id': row['id'],
        'entity_name': row['entity_name'],
        'amount': (row['total'] as num?)?.toDouble() ?? 0.0,
        'currency': row['currency'] ?? 'YER',
        'time': row['created_at'] ?? '',
      });
    }

    // فواتير المشتريات
    final purchaseInvoices = await db.rawQuery(
      "SELECT i.id, i.type, i.total, i.created_at, i.currency, "
      "CASE WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد') "
      "ELSE 'بدون مورد' END AS entity_name "
      "FROM invoices i LEFT JOIN suppliers s ON i.supplier_id = s.id "
      "WHERE i.type = 'purchase' AND i.is_return = 0 "
      "AND i.created_at >= ? AND i.created_at < ? "
      "ORDER BY i.created_at DESC",
      [startStr, endStr],
    );
    for (final row in purchaseInvoices) {
      operations.add({
        'type': 'purchase_invoice',
        'type_label': 'فاتورة مشتريات',
        'id': row['id'],
        'entity_name': row['entity_name'],
        'amount': (row['total'] as num?)?.toDouble() ?? 0.0,
        'currency': row['currency'] ?? 'YER',
        'time': row['created_at'] ?? '',
      });
    }

    // سندات القبض والصرف (باستخدام try/catch لأن الجدول قد لا يكون موجوداً)
    try {
      final vouchers = await db.rawQuery(
        "SELECT id, voucher_number, voucher_type, total_amount, date, currency, description "
        "FROM vouchers "
        "WHERE date >= ? AND date < ? "
        "ORDER BY date DESC",
        [dayStart.toIso8601String().substring(0, 10), dayEnd.toIso8601String().substring(0, 10)],
      );
      for (final row in vouchers) {
        final voucherType = row['voucher_type'] as String? ?? '';
        final isReceipt = voucherType.contains('receipt') || voucherType.contains('قبض');
        operations.add({
          'type': isReceipt ? 'receipt_voucher' : 'payment_voucher',
          'type_label': isReceipt ? 'سند قبض' : 'سند صرف',
          'id': row['id'],
          'entity_name': row['description'] ?? row['voucher_number'] ?? '',
          'amount': (row['total_amount'] as num?)?.toDouble() ?? 0.0,
          'currency': row['currency'] ?? 'YER',
          'time': row['date'] ?? '',
        });
      }
    } catch (_) {
      // جدول السندات غير موجود بعد
    }

    // المصروفات
    final expenses = await db.rawQuery(
      "SELECT id, title, amount, expense_date, currency, category "
      "FROM expenses "
      "WHERE expense_date >= ? AND expense_date < ? "
      "ORDER BY expense_date DESC",
      [startStr, endStr],
    );
    for (final row in expenses) {
      operations.add({
        'type': 'expense',
        'type_label': 'مصروف',
        'id': row['id'],
        'entity_name': row['title'] ?? (row['category'] ?? ''),
        'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
        'currency': row['currency'] ?? 'YER',
        'time': row['expense_date'] ?? '',
      });
    }

    // التحويلات النقدية
    final transfers = await db.rawQuery(
      "SELECT ct.id, ct.transfer_number, ct.amount, ct.currency, ct.created_at, "
      "cb_from.name AS from_name, cb_to.name AS to_name "
      "FROM cash_transfers ct "
      "LEFT JOIN cash_boxes cb_from ON ct.from_cash_box_id = cb_from.id "
      "LEFT JOIN cash_boxes cb_to ON ct.to_cash_box_id = cb_to.id "
      "WHERE ct.created_at >= ? AND ct.created_at < ? "
      "ORDER BY ct.created_at DESC",
      [startStr, endStr],
    );
    for (final row in transfers) {
      operations.add({
        'type': 'cash_transfer',
        'type_label': 'تحويل نقدي',
        'id': row['id'],
        'entity_name': '${row['from_name'] ?? ''} ← ${row['to_name'] ?? ''}',
        'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
        'currency': row['currency'] ?? 'YER',
        'time': row['created_at'] ?? '',
      });
    }

    // صرافة العملات
    try {
      final exchanges = await db.rawQuery(
        "SELECT ce.id, ce.exchange_number, ce.from_amount, ce.to_amount, ce.from_currency, "
        "ce.to_currency, ce.exchange_rate, ce.created_at, "
        "cb_from.name AS from_box_name, cb_to.name AS to_box_name "
        "FROM currency_exchanges ce "
        "LEFT JOIN cash_boxes cb_from ON ce.from_cash_box_id = cb_from.id "
        "LEFT JOIN cash_boxes cb_to ON ce.to_cash_box_id = cb_to.id "
        "WHERE ce.created_at >= ? AND ce.created_at < ? "
        "ORDER BY ce.created_at DESC",
        [startStr, endStr],
      );
      for (final row in exchanges) {
        operations.add({
          'type': 'currency_exchange',
          'type_label': 'صرافة عملات',
          'id': row['id'],
          'entity_name': '${row['from_currency'] ?? ''} → ${row['to_currency'] ?? ''}',
          'amount': (row['from_amount'] as num?)?.toDouble() ?? 0.0,
          'currency': row['from_currency'] ?? 'YER',
          'time': row['created_at'] ?? '',
        });
      }
    } catch (_) {
      // جدول صرافة العملات غير موجود بعد
    }

    // ترتيب حسب الوقت تنازلياً
    operations.sort((a, b) {
      final timeA = (a['time'] as String?) ?? '';
      final timeB = (b['time'] as String?) ?? '';
      return timeB.compareTo(timeA);
    });

    return operations;
  }

  /// جلب ملخص العمليات اليومية لتاريخ محدد
  /// Returns daily summary totals by category.
  Future<Map<String, double>> getDailySummary(DateTime date) async {
    final db = await database;
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final startStr = dayStart.toIso8601String();
    final endStr = dayEnd.toIso8601String();

    final Map<String, double> summary = {
      'total_sales': 0.0,
      'total_purchases': 0.0,
      'total_receipts': 0.0,
      'total_payments': 0.0,
      'total_expenses': 0.0,
      'total_transfers': 0.0,
    };

    // إجمالي المبيعات
    final salesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices "
      "WHERE type IN ('sale', 'pos') AND is_return = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_sales'] = (salesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // إجمالي المشتريات
    final purchasesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(total), 0.0) AS total FROM invoices "
      "WHERE type = 'purchase' AND is_return = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_purchases'] = (purchasesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // سندات القبض
    try {
      final receiptsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0.0) AS total FROM vouchers "
        "WHERE voucher_type LIKE '%receipt%' OR voucher_type LIKE '%قبض%' "
        "AND date >= ? AND date < ?",
        [dayStart.toIso8601String().substring(0, 10), dayEnd.toIso8601String().substring(0, 10)],
      );
      summary['total_receipts'] = (receiptsResult.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {}

    // سندات الصرف
    try {
      final paymentsResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0.0) AS total FROM vouchers "
        "WHERE (voucher_type LIKE '%payment%' OR voucher_type LIKE '%صرف%') "
        "AND date >= ? AND date < ?",
        [dayStart.toIso8601String().substring(0, 10), dayEnd.toIso8601String().substring(0, 10)],
      );
      summary['total_payments'] = (paymentsResult.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {}

    // المصروفات
    final expensesResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses "
      "WHERE expense_date >= ? AND expense_date < ?",
      [startStr, endStr],
    );
    summary['total_expenses'] = (expensesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // التحويلات
    final transfersResult = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0.0) AS total FROM cash_transfers "
      "WHERE created_at >= ? AND created_at < ?",
      [startStr, endStr],
    );
    summary['total_transfers'] = (transfersResult.first['total'] as num?)?.toDouble() ?? 0.0;

    return summary;
  }

  /// جلب الحسابات بدون حركة
  /// Returns accounts that have zero transactions.
  Future<List<Map<String, dynamic>>> getAccountsWithoutMovements() async {
    final db = await database;
    return await db.rawQuery(
      "SELECT a.id, a.name_ar, a.account_code, a.account_type, a.currency, a.balance "
      "FROM accounts a "
      "LEFT JOIN transactions t ON a.id = t.account_id "
      "WHERE a.is_active = 1 AND t.id IS NULL "
      "ORDER BY a.account_code",
    );
  }

  /// جلب تقرير أرباح الفواتير
  /// Returns profit per invoice (sale price - cost price).
  Future<List<Map<String, dynamic>>> getInvoiceProfitReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    String dateFilter = '';
    List<dynamic> args = [];
    if (startDate != null) {
      dateFilter += ' AND i.created_at >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final toDate = endDate.add(const Duration(days: 1));
      dateFilter += ' AND i.created_at < ?';
      args.add(toDate.toIso8601String());
    }

    return await db.rawQuery(
      "SELECT i.id AS invoice_id, i.type, i.total AS sale_total, i.currency, i.created_at, "
      "CASE WHEN i.customer_id IS NOT NULL THEN COALESCE(c.name, 'بدون عميل') "
      "WHEN i.supplier_id IS NOT NULL THEN COALESCE(s.name, 'بدون مورد') "
      "ELSE 'بدون عميل' END AS entity_name, "
      "COALESCE(SUM(ii.quantity * p.cost_price), 0.0) AS cost_total, "
      "i.total - COALESCE(SUM(ii.quantity * p.cost_price), 0.0) AS profit "
      "FROM invoices i "
      "LEFT JOIN customers c ON i.customer_id = c.id "
      "LEFT JOIN suppliers s ON i.supplier_id = s.id "
      "LEFT JOIN invoice_items ii ON ii.invoice_id = i.id "
      "LEFT JOIN products p ON ii.product_id = p.id "
      "WHERE i.is_return = 0 AND i.type IN ('sale', 'pos', 'purchase') "
      "$dateFilter "
      "GROUP BY i.id "
      "ORDER BY i.created_at DESC",
      args,
    );
  }

  /// جلب تقرير حركة المخزون
  /// Returns stock in/out movements per product.
  Future<List<Map<String, dynamic>>> getInventoryMovementReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    String dateFilter = '';
    List<dynamic> args = [];
    if (startDate != null) {
      dateFilter += ' AND i.created_at >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final toDate = endDate.add(const Duration(days: 1));
      dateFilter += ' AND i.created_at < ?';
      args.add(toDate.toIso8601String());
    }

    return await db.rawQuery(
      "SELECT p.id AS product_id, p.name_ar, p.item_code, p.current_stock, "
      "COALESCE(sales_data.qty_out, 0.0) AS qty_out, "
      "COALESCE(sales_data.revenue, 0.0) AS total_revenue, "
      "COALESCE(purchase_data.qty_in, 0.0) AS qty_in, "
      "COALESCE(purchase_data.cost, 0.0) AS total_cost "
      "FROM products p "
      "LEFT JOIN ("
      "  SELECT ii.product_id, SUM(ii.quantity) AS qty_out, SUM(ii.total_price) AS revenue "
      "  FROM invoice_items ii "
      "  INNER JOIN invoices i ON ii.invoice_id = i.id "
      "  WHERE i.type IN ('sale', 'pos') AND i.is_return = 0 $dateFilter "
      "  GROUP BY ii.product_id"
      ") sales_data ON p.id = sales_data.product_id "
      "LEFT JOIN ("
      "  SELECT ii.product_id, SUM(ii.quantity) AS qty_in, SUM(ii.total_price) AS cost "
      "  FROM invoice_items ii "
      "  INNER JOIN invoices i ON ii.invoice_id = i.id "
      "  WHERE i.type = 'purchase' AND i.is_return = 0 $dateFilter "
      "  GROUP BY ii.product_id"
      ") purchase_data ON p.id = purchase_data.product_id "
      "WHERE p.is_active = 1 AND (sales_data.qty_out IS NOT NULL OR purchase_data.qty_in IS NOT NULL) "
      "ORDER BY p.name_ar",
      [...args, ...args],
    );
  }

  /// جلب تقرير تكلفة المخزون
  /// Returns cost value of current stock per product.
  Future<List<Map<String, dynamic>>> getInventoryCostReport() async {
    final db = await database;
    return await db.rawQuery(
      "SELECT p.id, p.name_ar, p.item_code, p.barcode, "
      "p.current_stock, p.cost_price, p.sell_price, "
      "(p.current_stock * p.cost_price) AS stock_cost_value, "
      "(p.current_stock * p.sell_price) AS stock_sell_value, "
      "c.name AS category_name, w.name AS warehouse_name "
      "FROM products p "
      "LEFT JOIN categories c ON p.category_id = c.id "
      "LEFT JOIN warehouses w ON p.warehouse_id = w.id "
      "WHERE p.is_active = 1 AND p.current_stock > 0 "
      "ORDER BY stock_cost_value DESC",
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Stock Transfer methods (تحويل مخزني)
  // ══════════════════════════════════════════════════════════════

  /// إدراج تحويل مخزني وتحديث المخزون
  Future<int> insertStockTransfer(Map<String, dynamic> transferMap) async {
    final db = await database;
    final productId = transferMap['product_id'] as int;
    final quantity = (transferMap['quantity'] as num).toDouble();
    final fromWarehouseId = transferMap['from_warehouse_id'] as int;
    final toWarehouseId = transferMap['to_warehouse_id'] as int;

    return await db.transaction<int>((txn) async {
      // إدراج سجل التحويل
      final id = await txn.insert('stock_transfers', transferMap);

      // خصم الكمية من مخزن المصدر
      final fromProducts = await txn.query(
        'products',
        where: 'id = ? AND warehouse_id = ?',
        whereArgs: [productId, fromWarehouseId],
        limit: 1,
      );

      if (fromProducts.isNotEmpty) {
        final currentStock = (fromProducts.first['current_stock'] as num?)?.toDouble() ?? 0.0;
        await txn.update(
          'products',
          {
            'current_stock': (currentStock - quantity).clamp(0.0, double.infinity),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      // إضافة الكمية لمخزن الوجهة
      final sourceProduct = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );

      if (sourceProduct.isNotEmpty) {
        final productName = sourceProduct.first['name_ar'] as String;
        final toProduct = await txn.query(
          'products',
          where: 'name_ar = ? AND warehouse_id = ?',
          whereArgs: [productName, toWarehouseId],
          limit: 1,
        );

        if (toProduct.isNotEmpty) {
          final currentStock = (toProduct.first['current_stock'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'products',
            {
              'current_stock': currentStock + quantity,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [toProduct.first['id']],
          );
        } else {
          // إنشاء نسخة من المنتج في المخزن الهدف
          final newProduct = Map<String, dynamic>.from(sourceProduct.first);
          newProduct.remove('id');
          newProduct['warehouse_id'] = toWarehouseId;
          newProduct['current_stock'] = quantity;
          newProduct['created_at'] = DateTime.now().toIso8601String();
          newProduct['updated_at'] = DateTime.now().toIso8601String();
          await txn.insert('products', newProduct);
        }
      }

      return id;
    });
  }

  /// جلب جميع التحويلات المخزنية مع أسماء المستودعات والمنتجات
  Future<List<Map<String, dynamic>>> getAllStockTransfers() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT st.*,
        fw.name AS from_warehouse_name,
        tw.name AS to_warehouse_name,
        p.name_ar AS product_name
      FROM stock_transfers st
      LEFT JOIN warehouses fw ON st.from_warehouse_id = fw.id
      LEFT JOIN warehouses tw ON st.to_warehouse_id = tw.id
      LEFT JOIN products p ON st.product_id = p.id
      ORDER BY st.created_at DESC
    ''');
  }

  // ══════════════════════════════════════════════════════════════
  //  Stocktaking methods (جرد المخازن)
  // ══════════════════════════════════════════════════════════════

  /// إنشاء جلسة جرد مع عناصرها
  Future<int> createStocktakingSession(
    Map<String, dynamic> sessionMap,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    return await db.transaction<int>((txn) async {
      final sessionId = await txn.insert('stocktaking_sessions', sessionMap);

      for (final item in items) {
        item['session_id'] = sessionId;
        await txn.insert('stocktaking_items', item);
      }

      return sessionId;
    });
  }

  /// إكمال جلسة الجرد وتحديث المخزون الفعلي مع تسجيل الفرق والتدقيق
  Future<void> completeStocktakingSession(int sessionId) async {
    final db = await database;
    await db.transaction((txn) async {
      // جلب عناصر الجرد
      final items = await txn.query(
        'stocktaking_items',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

      // حساب المطابق وغير المطابق
      int matched = 0;
      int mismatched = 0;

      // تحديث المخزون لكل منتج بالكمية الفعلية + حساب وتسجيل الفرق + سجل التدقيق
      for (final item in items) {
        final productId = item['product_id'] as int;
        final systemQuantity = (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
        final actualQuantity = (item['actual_quantity'] as num).toDouble();
        final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;

        // حساب الفرق (variance) بين الكمية بالنظام والكمية الفعلية
        final variance = actualQuantity - systemQuantity;

        // جلب الكمية الحالية للمنتج قبل التحديث (للسجل)
        final productRows = await txn.query(
          'products',
          columns: ['current_stock'],
          where: 'id = ?',
          whereArgs: [productId],
        );
        final oldStock = productRows.isNotEmpty
            ? (productRows.first['current_stock'] as num?)?.toDouble() ?? 0.0
            : 0.0;

        // تحديث المخزون بالكمية الفعلية
        await txn.update(
          'products',
          {
            'current_stock': actualQuantity,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [productId],
        );

        // تحديث حقل الفرق في عنصر الجرد
        await txn.update(
          'stocktaking_items',
          {'variance': variance},
          where: 'id = ?',
          whereArgs: [item['id']],
        );

        // إضافة سجل تدقيق لكل منتج تغير مخزونه
        if (variance.abs() >= 0.005) {
          await txn.insert('audit_trail', {
            'action': 'stocktake_adjust',
            'table_name': 'products',
            'record_id': productId,
            'record_type': 'stock_adjustment',
            'old_values': oldStock.toString(),
            'new_values': actualQuantity.toString(),
            'user_name': null,
            'shift_id': null,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        if (variance.abs() < 0.005) {
          matched++;
        } else {
          mismatched++;
        }
      }

      // تحديث حالة الجرد إلى مكتمل
      await txn.update(
        'stocktaking_sessions',
        {
          'status': 'completed',
          'matched_items': matched,
          'mismatched_items': mismatched,
          'total_items': items.length,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  /// جلب جميع جلسات الجرد
  Future<List<Map<String, dynamic>>> getStocktakingSessions() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ss.*, w.name AS warehouse_name
      FROM stocktaking_sessions ss
      LEFT JOIN warehouses w ON ss.warehouse_id = w.id
      ORDER BY ss.created_at DESC
    ''');
  }

  /// جلب عناصر جلسة الجرد
  Future<List<Map<String, dynamic>>> getStocktakingItems(int sessionId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT si.*, p.name_ar AS product_name, p.current_stock
      FROM stocktaking_items si
      LEFT JOIN products p ON si.product_id = p.id
      WHERE si.session_id = ?
      ORDER BY p.name_ar ASC
    ''', [sessionId]);
  }

  /// جلب جميع الحركات المحاسبية للتصدير مع اسم الحساب
  Future<List<Map<String, dynamic>>> getAllTransactionsForExport() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t.*, a.name_ar AS account_name
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      ORDER BY t.date DESC
    ''');
  }

  // ══════════════════════════════════════════════════════════════
  //  Advanced Statistics / Charts query methods
  // ══════════════════════════════════════════════════════════════

  /// Monthly sales vs purchases for a given [year].
  /// Returns 12 rows (one per month) with `month`, `sales`, `purchases` columns.
  Future<List<Map<String, dynamic>>> getMonthlySalesVsPurchases(int year, {String? currency}) async {
    final db = await database;
    final currencyFilter = currency != null && currency.isNotEmpty ? " AND i.currency = '$currency'" : '';
    return await db.rawQuery('''
      SELECT m.month,
        COALESCE(s.total, 0.0) AS sales,
        COALESCE(p.total, 0.0) AS purchases
      FROM (
        SELECT 1 AS month UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION
        SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION
        SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
      ) m
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(total) AS total
        FROM invoices
        WHERE type = 'sale' AND is_return = 0
          AND strftime('%Y', created_at) = '$year'
          $currencyFilter
        GROUP BY month
      ) s ON m.month = s.month
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(total) AS total
        FROM invoices
        WHERE type = 'purchase' AND is_return = 0
          AND strftime('%Y', created_at) = '$year'
          $currencyFilter
        GROUP BY month
      ) p ON m.month = p.month
      ORDER BY m.month
    ''');
  }

  /// Revenue vs Expense breakdown for a given [year].
  /// Returns rows with `category`, `total`, `type` columns.
  Future<List<Map<String, dynamic>>> getRevenueExpenseBreakdown(int year, {String? currency}) async {
    final db = await database;
    final currencyFilter = currency != null && currency.isNotEmpty ? " AND currency = '$currency'" : '';
    final yearStr = year.toString();

    final results = <Map<String, dynamic>>[];

    // Revenue by invoice type
    final revenueData = await db.rawQuery('''
      SELECT
        CASE
          WHEN type = 'sale' AND is_return = 0 THEN 'مبيعات'
          WHEN type = 'purchase' AND is_return = 1 THEN 'مرتجع مشتريات'
          ELSE 'أخرى'
        END AS category,
        SUM(total) AS total,
        'إيرادات' AS type
      FROM invoices
      WHERE (type = 'sale' AND is_return = 0 OR type = 'purchase' AND is_return = 1)
        AND strftime('%Y', created_at) = ?
        $currencyFilter
      GROUP BY category
    ''', [yearStr]);
    results.addAll(revenueData);

    // Expenses by category
    final expenseData = await db.rawQuery('''
      SELECT
        COALESCE(category, 'مصاريف عامة') AS category,
        SUM(amount) AS total,
        'مصروفات' AS type
      FROM expenses
      WHERE strftime('%Y', expense_date) = ?
        $currencyFilter
      GROUP BY category
    ''', [yearStr]);
    results.addAll(expenseData);

    // Purchases as expense category
    final purchaseData = await db.rawQuery('''
      SELECT 'مشتريات' AS category,
        SUM(total) AS total,
        'مصروفات' AS type
      FROM invoices
      WHERE type = 'purchase' AND is_return = 0
        AND strftime('%Y', created_at) = ?
        $currencyFilter
    ''', [yearStr]);
    results.addAll(purchaseData);

    return results;
  }

  /// Daily sales trend for the last [days] days.
  /// Returns rows with `date`, `total` columns.
  Future<List<Map<String, dynamic>>> getDailySalesTrend(int days, {String? currency}) async {
    final db = await database;
    final currencyFilter = currency != null && currency.isNotEmpty ? " AND currency = '$currency'" : '';
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    return await db.rawQuery('''
      SELECT date(created_at) AS date, COALESCE(SUM(total), 0.0) AS total
      FROM invoices
      WHERE type = 'sale' AND is_return = 0
        AND date(created_at) >= ?
        $currencyFilter
      GROUP BY date(created_at)
      ORDER BY date(created_at) ASC
    ''', [startDateStr]);
  }

  /// Top products by sales amount.
  /// Returns rows with `product_name`, `total_quantity`, `total_amount` columns.
  Future<List<Map<String, dynamic>>> getTopProducts(int limit, {String? currency}) async {
    final db = await database;
    final currencyFilter = currency != null && currency.isNotEmpty ? " AND i.currency = '$currency'" : '';
    return await db.rawQuery('''
      SELECT ii.product_name,
        SUM(ii.quantity) AS total_quantity,
        SUM(ii.total_price) AS total_amount
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.type = 'sale' AND i.is_return = 0
        $currencyFilter
      GROUP BY ii.product_name
      ORDER BY total_amount DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Top customer balances.
  /// Returns rows with `name`, `balance`, `balance_type`, `currency` columns.
  Future<List<Map<String, dynamic>>> getTopCustomerBalances(int limit) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT name, balance, balance_type, currency
      FROM customers
      WHERE balance > 0
      ORDER BY balance DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Monthly cash flow (inflow vs outflow) for a given [year].
  /// Returns 12 rows with `month`, `inflow`, `outflow` columns.
  Future<List<Map<String, dynamic>>> getMonthlyCashFlow(int year, {String? currency}) async {
    final db = await database;
    final currencyFilter = currency != null && currency.isNotEmpty ? " AND currency = '$currency'" : '';
    return await db.rawQuery('''
      SELECT m.month,
        COALESCE(i.inflow, 0.0) AS inflow,
        COALESCE(o.outflow, 0.0) AS outflow
      FROM (
        SELECT 1 AS month UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION
        SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION
        SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
      ) m
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(paid_amount) AS inflow
        FROM invoices
        WHERE type = 'sale' AND is_return = 0 AND paid_amount > 0
          AND strftime('%Y', created_at) = '$year'
          $currencyFilter
        GROUP BY month
      ) i ON m.month = i.month
      LEFT JOIN (
        SELECT CAST(strftime('%m', created_at) AS INTEGER) AS month,
               SUM(total) AS outflow
        FROM expenses
        WHERE strftime('%Y', expense_date) = '$year'
          $currencyFilter
        GROUP BY month
      ) o ON m.month = o.month
      ORDER BY m.month
    ''');
  }

  // ══════════════════════════════════════════════════════════════
  //  Inventory Voucher Methods (سندات الجرد) - v22
  // ══════════════════════════════════════════════════════════════

  Future<String> getNextInventoryVoucherNumber() async {
    final db = await database;
    final now = DateTime.now();
    final prefix = 'IV-${now.year}${now.month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM inventory_vouchers WHERE voucher_number LIKE ?",
      ['$prefix%'],
    );
    final count = (result.first['cnt'] as num?)?.toInt() ?? 0;
    return '$prefix-${(count + 1).toString().padLeft(4, '0')}';
  }

  Future<int> insertInventoryVoucher(
    Map<String, dynamic> voucherMap,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    int voucherId = 0;
    await db.transaction((txn) async {
      // Insert voucher header
      voucherId = await txn.insert('inventory_vouchers', {
        ...voucherMap,
        'created_at': now,
        'updated_at': now,
      });

      double totalIncreaseValue = 0.0;
      double totalDecreaseValue = 0.0;

      for (final item in items) {
        final productId = item['product_id'] as int;
        final difference = (item['difference'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0.0;
        final totalValue = difference.abs() * unitCost;

        // Insert voucher item
        await txn.insert('inventory_voucher_items', {
          'voucher_id': voucherId,
          'product_id': productId,
          'system_quantity': (item['system_quantity'] as num?)?.toDouble() ?? 0.0,
          'actual_quantity': (item['actual_quantity'] as num?)?.toDouble() ?? 0.0,
          'difference': difference,
          'unit_cost': unitCost,
          'total_value': totalValue,
          'notes': item['notes'] as String?,
        });

        // Update product stock
        final product = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        if (product.isNotEmpty) {
          final currentStock = (product.first['current_stock'] as num?)?.toDouble() ?? 0.0;
          await txn.update('products', {
            'current_stock': currentStock + difference,
            'updated_at': now,
          }, where: 'id = ?', whereArgs: [productId]);
        }

        if (difference > 0) {
          totalIncreaseValue += totalValue;
        } else if (difference < 0) {
          totalDecreaseValue += totalValue;
        }
      }

      // Update voucher total value
      await txn.update('inventory_vouchers', {
        'total_value': totalIncreaseValue + totalDecreaseValue,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [voucherId]);

      // Get currency for this voucher
      final currency = voucherMap['currency'] as String? ?? 'YER';

      // Find accounts by code and currency
      // Inventory account code = 1300 + offset
      final inventoryAccount = await _findAccountByCodeAndCurrency(txn, '1300', currency);
      // COGS account code = 3200 + offset
      final cogsAccount = await _findAccountByCodeAndCurrency(txn, '3200', currency);

      // Journal entries for inventory increase (difference > 0)
      if (totalIncreaseValue > 0) {
        if (inventoryAccount != null) {
          final invAccId = inventoryAccount['id'] as int;
          // Debit Inventory (asset increase)
          await txn.insert('transactions', {
            'account_id': invAccId,
            'journal_id': journalId,
            'debit': totalIncreaseValue,
            'credit': 0.0,
            'description': 'سند جرد - زيادة مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, invAccId, totalIncreaseValue, 0.0, now);
        }
        if (cogsAccount != null) {
          final cogsAccId = cogsAccount['id'] as int;
          // Credit COGS (reducing cost of goods sold)
          await txn.insert('transactions', {
            'account_id': cogsAccId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': totalIncreaseValue,
            'description': 'سند جرد - زيادة مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, cogsAccId, 0.0, totalIncreaseValue, now);
        }
      }

      // Journal entries for inventory decrease (difference < 0)
      if (totalDecreaseValue > 0) {
        if (cogsAccount != null) {
          final cogsAccId = cogsAccount['id'] as int;
          // Debit COGS (increasing cost)
          await txn.insert('transactions', {
            'account_id': cogsAccId,
            'journal_id': journalId,
            'debit': totalDecreaseValue,
            'credit': 0.0,
            'description': 'سند جرد - نقص مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, cogsAccId, totalDecreaseValue, 0.0, now);
        }
        if (inventoryAccount != null) {
          final invAccId = inventoryAccount['id'] as int;
          // Credit Inventory (asset decrease)
          await txn.insert('transactions', {
            'account_id': invAccId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': totalDecreaseValue,
            'description': 'سند جرد - نقص مخزون',
            'date': voucherMap['date'] as String? ?? now.substring(0, 10),
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, invAccId, 0.0, totalDecreaseValue, now);
        }
      }
    });

    return voucherId;
  }

  /// Helper: find account by base code and currency
  Future<Map<String, dynamic>?> _findAccountByCodeAndCurrency(Transaction txn, String baseCode, String currency) async {
    // Determine code offset based on currency
    String codeOffset = '0';
    if (currency == 'SAR') {
      codeOffset = '1';
    } else if (currency == 'USD') {
      codeOffset = '2';
    }
    final actualCode = (int.parse(baseCode) + int.parse(codeOffset)).toString();
    final result = await txn.query('accounts', where: 'account_code = ? AND currency = ?', whereArgs: [actualCode, currency], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getInventoryVouchers({String? searchQuery}) async {
    final db = await database;
    String query = '''
      SELECT iv.*, w.name as warehouse_name
      FROM inventory_vouchers iv
      LEFT JOIN warehouses w ON iv.warehouse_id = w.id
    ''';
    List<dynamic> args = [];
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query += ' WHERE iv.voucher_number LIKE ? OR iv.description LIKE ? OR w.name LIKE ?';
      final likeQuery = '%$searchQuery%';
      args = [likeQuery, likeQuery, likeQuery];
    }
    query += ' ORDER BY iv.created_at DESC';
    return await db.rawQuery(query, args);
  }

  Future<Map<String, dynamic>?> getInventoryVoucherDetails(int voucherId) async {
    final db = await database;
    final voucherResult = await db.rawQuery('''
      SELECT iv.*, w.name as warehouse_name
      FROM inventory_vouchers iv
      LEFT JOIN warehouses w ON iv.warehouse_id = w.id
      WHERE iv.id = ?
    ''', [voucherId]);
    if (voucherResult.isEmpty) return null;

    final items = await db.rawQuery('''
      SELECT ivi.*, p.name_ar as product_name, p.barcode, p.item_code
      FROM inventory_voucher_items ivi
      LEFT JOIN products p ON ivi.product_id = p.id
      WHERE ivi.voucher_id = ?
      ORDER BY ivi.id
    ''', [voucherId]);

    return {
      ...voucherResult.first,
      'items': items,
    };
  }

  // ══════════════════════════════════════════════════════════════
  //  Annual Posting Methods (الترحيل السنوي) - v22
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getFiscalYears() async {
    final db = await database;
    return await db.query('fiscal_years', orderBy: 'year DESC');
  }

  Future<bool> isFiscalYearClosed(int year) async {
    final db = await database;
    final result = await db.query('fiscal_years', where: 'year = ? AND status = ?', whereArgs: [year, 'closed'], limit: 1);
    return result.isNotEmpty;
  }

  /// Check if a date falls in a closed fiscal year
  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final db = await database;
    final year = date.year;
    final result = await db.query(
      'fiscal_years',
      where: 'year = ? AND status = ?',
      whereArgs: [year, 'closed'],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Log an audit trail event (non-critical — errors are caught and printed)
  Future<void> logAuditEvent({
    required String action,
    required String tableName,
    int? recordId,
    String? recordType,
    String? oldValues,
    String? newValues,
    String? userName,
    int? shiftId,
  }) async {
    final db = await database;
    try {
      await db.insert('audit_trail', {
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'record_type': recordType,
        'old_values': oldValues,
        'new_values': newValues,
        'user_name': userName,
        'shift_id': shiftId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Audit log error (non-critical): $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Accounting Safeguards (قفل الفترة، توازن القيد، الترقيم)
  // ══════════════════════════════════════════════════════════════

  /// التحقق من أن الفترة المحاسبية مفتوحة قبل إجراء أي عملية
  /// يمنع تعديل أو إضافة قيود في فترات مغلقة
  Future<void> _checkFiscalPeriodOpen(String dateStr) async {
    final db = await database;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return;
    final year = date.year;

    // تحقق من وجود سنة مالية مقفلة لهذه الفترة
    final result = await db.query(
      'fiscal_years',
      where: 'year = ? AND status = ?',
      whereArgs: [year, 'closed'],
      limit: 1,
    );
    if (result.isNotEmpty) {
      throw Exception('الفترة المحاسبية للعام $year مغلقة. لا يمكن إجراء عمليات في فترة مقفلة.');
    }
  }

  /// الحصول على الرقم التسلسلي التالي للفواتير بدون فجوات
  /// يستخدم MAX بدلاً من COUNT لضمان عدم وجود فجوات حتى بعد الحذف
  Future<int> getNextInvoiceSequence(String datePrefix, String invoiceType) async {
    final db = await database;
    // البحث عن أكبر رقم تسلسلي موجود لهذا اليوم وهذا النوع
    final result = await db.rawQuery(
      "SELECT id FROM invoices WHERE id LIKE ? AND type = ? ORDER BY id DESC LIMIT 1",
      ['$datePrefix%', invoiceType],
    );
    if (result.isEmpty) return 1;

    final lastId = result.first['id'] as String;
    // استخراج الرقم التسلسلي من المعرف: POS-YYYYMMDD-NNNN → NNNN
    final parts = lastId.split('-');
    if (parts.length >= 3) {
      final lastSeq = int.tryParse(parts.last) ?? 0;
      return lastSeq + 1;
    }
    return 1;
  }

  /// التحقق من تجاوز سقف الدين للعميل
  /// يرجع true إذا تجاوز السقف، false إذا لم يتجاوز
  Future<bool> isCustomerOverDebtCeiling(int customerId, double additionalAmount) async {
    final db = await database;
    final customer = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (customer.isEmpty) return false;

    final debtCeiling = (customer.first['debt_ceiling'] as num?)?.toDouble() ?? 0.0;
    if (debtCeiling <= 0) return false; // لا يوجد سقف محدد

    final currentBalance = (customer.first['balance'] as num?)?.toDouble() ?? 0.0;
    return (currentBalance + additionalAmount) > debtCeiling;
  }

  /// التحقق من تجاوز سقف الدين للمورد
  Future<bool> isSupplierOverDebtCeiling(int supplierId, double additionalAmount) async {
    final db = await database;
    final supplier = await db.query('suppliers', where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (supplier.isEmpty) return false;

    final debtCeiling = (supplier.first['debt_ceiling'] as num?)?.toDouble() ?? 0.0;
    if (debtCeiling <= 0) return false;

    final currentBalance = (supplier.first['balance'] as num?)?.toDouble() ?? 0.0;
    return (currentBalance + additionalAmount) > debtCeiling;
  }

  /// حساب مكاسب/خسائر الصرف الأجنبي
  /// تُحسب عند إقفال الفترة أو عند تسوية حساب بعملة مختلفة
  /// formula: gain/loss = (base_amount * current_rate) - (base_amount * original_rate)
  Future<double> calculateExchangeGainLoss({
    required double baseAmount,
    required double originalRate,
    required double currentRate,
  }) async {
    if (originalRate <= 0 || currentRate <= 0) return 0.0;
    final valueAtOriginalRate = baseAmount / originalRate;
    final valueAtCurrentRate = baseAmount / currentRate;
    // إذا كان الفرق إيجابياً = مكسب صرف، سلبياً = خسارة صرف
    return valueAtCurrentRate - valueAtOriginalRate;
  }

  /// إنشاء قيد محاسبي لمكاسب/خسائر الصرف الأجنبي
  Future<void> recordExchangeGainLoss({
    required int accountId,
    required double gainLossAmount,
    required String currency,
    required String referenceId,
  }) async {
    if (gainLossAmount.abs() < 0.01) return;

    final db = await database;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    // البحث عن حساب مكاسب/خسائر الصرف (إن وجد) أو استخدام حساب المصاريف
    var exchangeAccountId = await _getOrCreateExchangeAccount();

    await db.transaction((txn) async {
      if (gainLossAmount > 0) {
        // مكسب صرف: مدين = الحساب الأصلي، دائن = حساب مكاسب الصرف
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': gainLossAmount.abs(),
          'credit': 0.0,
          'description': 'مكاسب صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await txn.insert('transactions', {
          'account_id': exchangeAccountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': gainLossAmount.abs(),
          'description': 'مكاسب صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await _updateAccountBalanceWithJournal(txn, accountId, gainLossAmount.abs(), 0.0, now);
        await _updateAccountBalanceWithJournal(txn, exchangeAccountId, 0.0, gainLossAmount.abs(), now);
      } else {
        // خسارة صرف: مدين = حساب خسائر الصرف، دائن = الحساب الأصلي
        await txn.insert('transactions', {
          'account_id': exchangeAccountId,
          'journal_id': journalId,
          'debit': gainLossAmount.abs(),
          'credit': 0.0,
          'description': 'خسائر صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await txn.insert('transactions', {
          'account_id': accountId,
          'journal_id': journalId,
          'debit': 0.0,
          'credit': gainLossAmount.abs(),
          'description': 'خسائر صرف $currency - $referenceId',
          'date': now.substring(0, 10),
          'created_at': now,
        });
        await _updateAccountBalanceWithJournal(txn, exchangeAccountId, gainLossAmount.abs(), 0.0, now);
        await _updateAccountBalanceWithJournal(txn, accountId, 0.0, gainLossAmount.abs(), now);
      }
    });
  }

  /// الحصول على أو إنشاء حساب مكاسب/خسائر الصرف الأجنبي
  Future<int> _getOrCreateExchangeAccount() async {
    final db = await database;
    // البحث عن حساب مكاسب/خسائر الصرف
    final existing = await db.query(
      'accounts',
      where: "account_code LIKE '53%' AND is_system = 1",
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    // إنشاء حساب جديد
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('accounts', {
      'name_ar': 'مكاسب/خسائر فروقات الصرف',
      'name_en': 'Exchange Rate Gains/Losses',
      'account_code': '5300',
      'account_type': 'EXPENSE',
      'balance': 0.0,
      'currency': 'YER',
      'balance_type': 'credit',
      'is_active': 1,
      'is_system': 1,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  /// التحقق الإلزامي من توازن القيد المزدوج قبل الحفظ
  /// يُستخدم كدالة مساعدة للتأكد من أن مجموع المدين = مجموع الدائن
  void _assertJournalBalance(List<Map<String, dynamic>> entries) {
    final totalDebit = entries.fold(0.0, (sum, e) => sum + ((e['debit'] as num?)?.toDouble() ?? 0.0));
    final totalCredit = entries.fold(0.0, (sum, e) => sum + ((e['credit'] as num?)?.toDouble() ?? 0.0));
    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception('القيد غير متوازن: المدين = $totalDebit، الدائن = $totalCredit. يجب أن يتساوى المدين والدائن.');
    }
  }

  Future<Map<String, double>> getYearProfitLoss(int year) async {
    final db = await database;
    final yearStart = '$year-01-01';
    final yearEnd = '$year-12-31';

    // Sum revenue accounts balance
    final revenueResult = await db.rawQuery('''
      SELECT COALESCE(SUM(balance), 0.0) as total
      FROM accounts
      WHERE account_type = 'REVENUE' AND is_active = 1
    ''');
    final totalRevenue = (revenueResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Sum cost accounts balance
    final costResult = await db.rawQuery('''
      SELECT COALESCE(SUM(balance), 0.0) as total
      FROM accounts
      WHERE account_type = 'COST' AND is_active = 1
    ''');
    final totalCosts = (costResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Sum expense accounts balance
    final expenseResult = await db.rawQuery('''
      SELECT COALESCE(SUM(balance), 0.0) as total
      FROM accounts
      WHERE account_type = 'EXPENSE' AND is_active = 1
    ''');
    final totalExpenses = (expenseResult.first['total'] as num?)?.toDouble() ?? 0.0;

    final netProfit = totalRevenue - totalCosts - totalExpenses;

    return {
      'revenue': totalRevenue,
      'costs': totalCosts,
      'expenses': totalExpenses,
      'netProfit': netProfit,
    };
  }

  Future<void> performAnnualPosting(int year) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final journalId = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Check if already closed
      final existing = await txn.query('fiscal_years', where: 'year = ? AND status = ?', whereArgs: [year, 'closed'], limit: 1);
      if (existing.isNotEmpty) {
        throw Exception('السنة المالية $year مغلقة بالفعل');
      }

      // Get all revenue accounts
      final revenueAccounts = await txn.query('accounts', where: 'account_type = ? AND is_active = 1', whereArgs: ['REVENUE']);

      // Get all cost accounts
      final costAccounts = await txn.query('accounts', where: 'account_type = ? AND is_active = 1', whereArgs: ['COST']);

      // Get all expense accounts
      final expenseAccounts = await txn.query('accounts', where: 'account_type = ? AND is_active = 1', whereArgs: ['EXPENSE']);

      // Get retained earnings accounts (one per currency)
      final retainedEarningsAccounts = await txn.query('accounts', where: 'account_code LIKE ? AND is_active = 1', whereArgs: ['290%']);

      // Calculate net profit per currency
      final Map<String, double> revenuePerCurrency = {};
      final Map<String, double> costPerCurrency = {};
      final Map<String, double> expensePerCurrency = {};

      for (final acc in revenueAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
        revenuePerCurrency[currency] = (revenuePerCurrency[currency] ?? 0.0) + balance;
      }

      for (final acc in costAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
        costPerCurrency[currency] = (costPerCurrency[currency] ?? 0.0) + balance;
      }

      for (final acc in expenseAccounts) {
        final currency = acc['currency'] as String? ?? 'YER';
        final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
        expensePerCurrency[currency] = (expensePerCurrency[currency] ?? 0.0) + balance;
      }

      // All currencies that have activity
      final allCurrencies = {...revenuePerCurrency.keys, ...costPerCurrency.keys, ...expensePerCurrency.keys};

      double totalNetProfitYER = 0.0;

      for (final currency in allCurrencies) {
        final rev = revenuePerCurrency[currency] ?? 0.0;
        final cost = costPerCurrency[currency] ?? 0.0;
        final exp = expensePerCurrency[currency] ?? 0.0;
        final netForCurrency = rev - cost - exp;

        // Find retained earnings account for this currency
        final reAccount = retainedEarningsAccounts.where((a) => a['currency'] == currency).firstOrNull;
        if (reAccount == null) continue;
        final reAccId = reAccount['id'] as int;

        // Close revenue accounts: Debit Revenue, Credit Retained Earnings
        for (final acc in revenueAccounts.where((a) => a['currency'] == currency)) {
          final accId = acc['id'] as int;
          final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
          if (balance == 0.0) continue;

          // Revenue accounts have credit balance, to close we debit them
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': journalId,
            'debit': balance,
            'credit': 0.0,
            'description': 'إقفال إيرادات السنة $year',
            'date': '$year-12-31',
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, accId, balance, 0.0, now);

          // Credit Retained Earnings
          await txn.insert('transactions', {
            'account_id': reAccId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': balance,
            'description': 'ترحيل أرباح السنة $year',
            'date': '$year-12-31',
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, reAccId, 0.0, balance, now);
        }

        // Close cost accounts: Debit Retained Earnings, Credit Cost
        for (final acc in costAccounts.where((a) => a['currency'] == currency)) {
          final accId = acc['id'] as int;
          final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
          if (balance == 0.0) continue;

          // Cost accounts have debit balance, to close we credit them
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': balance,
            'description': 'إقفال تكاليف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, accId, 0.0, balance, now);

          // Debit Retained Earnings
          await txn.insert('transactions', {
            'account_id': reAccId,
            'journal_id': journalId,
            'debit': balance,
            'credit': 0.0,
            'description': 'ترحيل تكاليف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, reAccId, balance, 0.0, now);
        }

        // Close expense accounts: Debit Retained Earnings, Credit Expense
        for (final acc in expenseAccounts.where((a) => a['currency'] == currency)) {
          final accId = acc['id'] as int;
          final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
          if (balance == 0.0) continue;

          // Expense accounts have debit balance, to close we credit them
          await txn.insert('transactions', {
            'account_id': accId,
            'journal_id': journalId,
            'debit': 0.0,
            'credit': balance,
            'description': 'إقفال مصاريف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, accId, 0.0, balance, now);

          // Debit Retained Earnings
          await txn.insert('transactions', {
            'account_id': reAccId,
            'journal_id': journalId,
            'debit': balance,
            'credit': 0.0,
            'description': 'ترحيل مصاريف السنة $year',
            'date': '$year-12-31',
            'created_at': now,
          });
          await _updateAccountBalanceWithJournal(txn, reAccId, balance, 0.0, now);
        }

        // Accumulate for total (using YER as base)
        if (currency == 'YER') {
          totalNetProfitYER += netForCurrency;
        }
      }

      // Create or update fiscal year record
      final existingFY = await txn.query('fiscal_years', where: 'year = ?', whereArgs: [year], limit: 1);
      if (existingFY.isNotEmpty) {
        await txn.update('fiscal_years', {
          'status': 'closed',
          'net_profit': totalNetProfitYER,
          'closed_at': now,
          'updated_at': now,
        }, where: 'year = ?', whereArgs: [year]);
      } else {
        await txn.insert('fiscal_years', {
          'year': year,
          'start_date': '$year-01-01',
          'end_date': '$year-12-31',
          'status': 'closed',
          'net_profit': totalNetProfitYER,
          'closed_at': now,
          'notes': 'ترحيل سنوي تلقائي',
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }
}
