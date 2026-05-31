import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import '../../core/security/db_encryption.dart';
import '../../core/utils/money_helper.dart';
import 'services/journal_service.dart';
import 'repositories/account_repository.dart';
import 'repositories/customer_repository.dart';
import 'repositories/invoice_repository.dart';
import 'repositories/product_repository.dart';
import 'repositories/supplier_repository.dart';
import 'repositories/expense_repository.dart';
import 'repositories/reference_data_repository.dart';
import 'services/cash_box_service.dart';
import 'services/stock_service.dart';
import 'services/shift_service.dart';
import 'repositories/order_repository.dart';
import 'services/report_service.dart';
import 'services/audit_service.dart';
import 'services/costing_engine_service.dart';
import 'services/bank_reconciliation_service.dart';
import '../models/account_model.dart';
import '../models/customer_model.dart';
import '../models/product_model.dart';
import '../models/invoice_model.dart';

class DatabaseHelper {
  /// Log a migration error instead of silently swallowing it (H-07)
  /// This helps debug database issues during upgrades.
  static void logMigrationError(String operation, dynamic error) {
    debugPrint('⚠️ DB Migration Warning [$operation]: $error');
    // Non-critical: migrations may fail if column already exists (idempotent)
  }
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  // C-08: Sub-services for God class decomposition
  late final JournalService journal = JournalService(this);
  late final AccountRepository accounts = AccountRepository(this);
  late final CustomerRepository customers = CustomerRepository(this);
  late final InvoiceRepository invoices = InvoiceRepository(this);
  late final ProductRepository products = ProductRepository(this);
  late final SupplierRepository suppliers = SupplierRepository(this);
  late final ExpenseRepository expenses = ExpenseRepository(this);
  late final CashBoxService cashBoxes = CashBoxService(this);
  late final ReferenceDataRepository refData = ReferenceDataRepository(this);
  late final StockService stock = StockService(this);
  late final ShiftService shifts = ShiftService(this);
  late final OrderRepository orders = OrderRepository(this);
  late final ReportService reports = ReportService(this);
  late final AuditService audit = AuditService(this);
  late final CostingEngineService costingEngine = CostingEngineService(this);
  late final BankReconciliationService bankReconciliation = BankReconciliationService(this);

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static const int _databaseVersion = 43;
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

    final encryptionKey = await DbEncryption.getOrGenerateKey();
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      password: encryptionKey,
      onConfigure: (db) async {
        // C-06: Enable foreign key enforcement early (before onCreate/onUpgrade)
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: (db) async {
        // Enable foreign key enforcement (M-06)
        // SQLite doesn't enforce FK constraints by default
        await db.execute('PRAGMA foreign_keys = ON');
      },
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
        balance INTEGER NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'YER',
        linked_cash_box_id INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_system INTEGER NOT NULL DEFAULT 0,
        debt_ceiling INTEGER NOT NULL DEFAULT 0,
        balance_type TEXT NOT NULL DEFAULT 'debit',
        -- Fix #9: Default 'debit' is correct for ASSET/EXPENSE which are the most common
        -- newly created accounts. LIABILITY/REVENUE/EQUITY accounts use 'credit' but
        -- those are typically seeded or set explicitly during creation.
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
        currency TEXT NOT NULL DEFAULT 'YER',
        costing_method TEXT NOT NULL DEFAULT 'weighted_average',
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
        balance INTEGER NOT NULL DEFAULT 0,
        balance_type TEXT NOT NULL DEFAULT 'credit',
        currency TEXT NOT NULL DEFAULT 'YER',
        debt_ceiling INTEGER NOT NULL DEFAULT 0,
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
        unit_price INTEGER NOT NULL DEFAULT 0,
        total_price INTEGER NOT NULL DEFAULT 0,
        unit_cost INTEGER NOT NULL DEFAULT 0,
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
        debit INTEGER NOT NULL DEFAULT 0,
        credit INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        balance_type TEXT,
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
        balance INTEGER NOT NULL DEFAULT 0,
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

    // Employees
    await db.execute('''
      CREATE TABLE employees (
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


    // Quotations
    await db.execute('''
      CREATE TABLE quotations (
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

    // Quotation Items
    await db.execute('''
      CREATE TABLE quotation_items (
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

    // Purchase Orders
    await db.execute('''
      CREATE TABLE purchase_orders (
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

    // Purchase Order Items
    await db.execute('''
      CREATE TABLE purchase_order_items (
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

    // Sales Orders
    await db.execute('''
      CREATE TABLE sales_orders (
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

    // Sales Order Items
    await db.execute('''
      CREATE TABLE sales_order_items (
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


    // Shifts (الورديات)
    await db.execute('''
      CREATE TABLE shifts (
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

    // Currency Exchanges (صرافة العملات) - v12
    await db.execute('''
      CREATE TABLE IF NOT EXISTS currency_exchanges (
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

    // Cash Transfers (تحويل بين الصناديق) - v12
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_transfers (
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

    // Voucher line items (بنود السند) - v18
    await db.execute('''
      CREATE TABLE voucher_items (
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
        total_value INTEGER NOT NULL DEFAULT 0,
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
        unit_cost INTEGER NOT NULL DEFAULT 0,
        total_value INTEGER NOT NULL DEFAULT 0,
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
        net_profit INTEGER NOT NULL DEFAULT 0,
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

    // Unit Conversions (was only in migrations before, now in _onCreate for fresh installs)
    await db.execute('''
      CREATE TABLE unit_conversions (
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
    await db.execute('CREATE INDEX idx_unit_conversions_product ON unit_conversions (product_id)');

    // Stock Movements (was only in migrations before, now in _onCreate for fresh installs)
    await db.execute('''
      CREATE TABLE stock_movements (
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
    await db.execute('CREATE INDEX idx_stock_movements_product ON stock_movements (product_id)');
    await db.execute('CREATE INDEX idx_stock_movements_type ON stock_movements (movement_type)');
    await db.execute('CREATE INDEX idx_stock_movements_ref ON stock_movements (reference_type, reference_id)');

    // Held Orders (POS) - v33
    await db.execute('''
      CREATE TABLE held_orders (
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
    await db.execute('CREATE INDEX idx_held_orders_shift ON held_orders (shift_id)');

    // Inventory Cost Layers (طبقات تكلفة المخزون) - v38
    await db.execute('''
      CREATE TABLE inventory_cost_layers (
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
    await db.execute('CREATE INDEX idx_cost_layers_product ON inventory_cost_layers (product_id)');
    await db.execute('CREATE INDEX idx_cost_layers_fifo ON inventory_cost_layers (product_id, acquisition_date, quantity_remaining) WHERE is_fully_consumed = 0');
    await db.execute('CREATE INDEX idx_cost_layers_consumed ON inventory_cost_layers (is_fully_consumed)');

    // Movement Cost Allocations (تخصيصات تكلفة الحركة) - v38
    await db.execute('''
      CREATE TABLE movement_cost_allocations (
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
    await db.execute('CREATE INDEX idx_mca_product ON movement_cost_allocations (product_id)');
    await db.execute('CREATE INDEX idx_mca_layer ON movement_cost_allocations (cost_layer_id)');
    await db.execute('CREATE INDEX idx_mca_invoice ON movement_cost_allocations (invoice_id)');

    // Bank Reconciliations (التسوية البنكية) - v38
    await db.execute('''
      CREATE TABLE bank_reconciliations (
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
    await db.execute('CREATE INDEX idx_bank_recon_cash_box ON bank_reconciliations (cash_box_id)');
    await db.execute('CREATE INDEX idx_bank_recon_status ON bank_reconciliations (status)');
    await db.execute('CREATE INDEX idx_bank_recon_number ON bank_reconciliations (reconciliation_number)');

    // Bank Statement Lines (بنود كشف الحساب البنكي) - v38
    await db.execute('''
      CREATE TABLE bank_statement_lines (
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
    await db.execute('CREATE INDEX idx_bank_stmt_recon ON bank_statement_lines (reconciliation_id)');
    await db.execute('CREATE INDEX idx_bank_stmt_cash_box ON bank_statement_lines (cash_box_id)');
    await db.execute('CREATE INDEX idx_bank_stmt_status ON bank_statement_lines (match_status)');
    await db.execute('CREATE INDEX idx_bank_stmt_date ON bank_statement_lines (transaction_date)');

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

  /// Shared account templates: [nameAr, nameEn, baseCode, accountType, parentBaseCode]
  /// parentBaseCode = null means this is a root/group account
  /// Used by both _seedDefaultAccounts and _seedAccountsForCurrency.
  static const List<List<dynamic>> _defaultAccountTemplates = [
    // ── الأصول (Assets) ──
    ['حساب الأصول', 'Assets Account', 1000, 'ASSET', null],
    ['حساب الصناديق والبنوك', 'Cash & Banks Account', 1100, 'ASSET', 1000],
    ['حساب العملاء', 'Customers Account', 1200, 'ASSET', 1000],
    ['المخزون', 'Inventory Account', 1300, 'ASSET', 1000],
    // ── الخصوم (Liabilities) ──
    ['حساب الخصوم', 'Liabilities Account', 2000, 'LIABILITY', null],
    ['حساب الموردين', 'Suppliers Account', 2100, 'LIABILITY', 2000],
    ['ضريبة القيمة المضافة', 'VAT Payable', 2300, 'LIABILITY', 2000],
    // ── حقوق الملكية (Equity) ──
    ['حقوق الملكية', 'Equity Account', 2900, 'EQUITY', null],
    ['رصيد افتتاحي', 'Opening Balance Equity', 2901, 'EQUITY', 2900],
    ['الأرباح المحتجزة', 'Retained Earnings', 2910, 'EQUITY', 2900],
    // ── التكاليف (Costs) ──
    ['حساب التكاليف', 'Cost Account', 3000, 'COST', null],
    ['حساب المشتريات', 'Purchases Account', 3100, 'COST', 3000],
    ['تكلفة البضاعة المباعة', 'COGS Account', 3200, 'COST', 3000],
    // ── الإيرادات (Revenue) ──
    ['حساب الإيرادات', 'Revenue Account', 4000, 'REVENUE', null],
    ['حساب المبيعات', 'Sales Account', 4100, 'REVENUE', 4000],
    ['خصم مشتريات مكتسب', 'Purchase Discount Earned', 4600, 'REVENUE', 4000],
    // ── المصروفات (Expenses) ──
    ['حساب المصاريف', 'Expenses Account', 5000, 'EXPENSE', null],
    ['حساب الموظفين', 'Employees Account', 5100, 'EXPENSE', 5000],
    ['اجور النقل', 'Transport Charges', 5200, 'EXPENSE', 5000],
    ['مصاريف بنكية', 'Bank Charges', 5250, 'EXPENSE', 5000],
    ['خسائر فروقات الصرف', 'Exchange Rate Losses', 5300, 'EXPENSE', 5000],
    ['خصم مسموح به', 'Discount Allowed', 5400, 'EXPENSE', 5000],
    ['خسارة تفاوت الجرد', 'Inventory Variance Loss', 5500, 'EXPENSE', 5000],
    // ── إيرادات أخرى (Other Revenue) ──
    ['مكاسب فروقات الصرف', 'Exchange Rate Gains', 4700, 'REVENUE', 4000],
    ['إيراد تفاوت الجرد', 'Inventory Variance Income', 4400, 'REVENUE', 4000],
  ];

  Future<void> _seedDefaultAccounts(Database db) async {
    // Only seed if accounts don't already exist
    final existing = await db.query('accounts', where: 'account_code = ?', whereArgs: ['1000'], limit: 1);
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toIso8601String();

    // Use shared account templates (M-07)
    final templates = _defaultAccountTemplates;

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

      // Track inserted account IDs by code for parent_id resolution
      final codeToId = <String, int>{};

      // First pass: insert all accounts (root accounts first, then children)
      // Sort to ensure parent accounts are inserted before children
      final sortedTemplates = List<List<dynamic>>.from(templates);
      sortedTemplates.sort((a, b) {
        final parentA = a[4] as int?;
        final parentB = b[4] as int?;
        // Root accounts (parent == null) come first
        if (parentA == null && parentB != null) return -1;
        if (parentA != null && parentB == null) return 1;
        return 0;
      });

      for (final template in sortedTemplates) {
        final baseCode = template[2] as int;
        final actualCode = (baseCode + codeOffset).toString();
        final accountType = template[3] as String;
        final parentBaseCode = template[4] as int?;

        // Resolve parent_id from previously inserted accounts
        int? parentId;
        if (parentBaseCode != null) {
          final parentCode = (parentBaseCode + codeOffset).toString();
          parentId = codeToId[parentCode];
        }

        final id = await db.insert('accounts', {
          'name_ar': '${template[0]} ($currencySymbol)',
          'name_en': '${template[1]} ($currencyCode)',
          'account_code': actualCode,
          'account_type': accountType,
          'balance': 0,
          'currency': currencyCode,
          'balance_type': (accountType == 'ASSET' || accountType == 'COST' || accountType == 'EXPENSE') ? 'debit' : 'credit',
          'parent_id': parentId,
          'is_active': 1,
          'is_system': 1,
          'created_at': now,
          'updated_at': now,
        });
        codeToId[actualCode] = id;
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

    // Use shared account templates (M-07)
    final templates = _defaultAccountTemplates;

    // Track inserted account IDs by code for parent_id resolution
    final codeToId = <String, int>{};

    // Sort to ensure parent accounts are inserted before children
    final sortedTemplates = List<List<dynamic>>.from(templates);
    sortedTemplates.sort((a, b) {
      final parentA = a[4] as int?;
      final parentB = b[4] as int?;
      if (parentA == null && parentB != null) return -1;
      if (parentA != null && parentB == null) return 1;
      return 0;
    });

    for (final template in sortedTemplates) {
      final actualCode = ((template[2] as int) + codeOffset).toString();
      final accountType = template[3] as String;
      final parentBaseCode = template[4] as int?;

      // Resolve parent_id from previously inserted accounts
      int? parentId;
      if (parentBaseCode != null) {
        final parentCode = (parentBaseCode + codeOffset).toString();
        parentId = codeToId[parentCode];
      }

      final id = await db.insert('accounts', {
        'name_ar': '${template[0]} ($currencySymbol)',
        'name_en': '${template[1]} ($currencyCode)',
        'account_code': actualCode,
        'account_type': accountType,
        'balance': 0,
        'currency': currencyCode,
        'balance_type': (accountType == 'ASSET' || accountType == 'COST' || accountType == 'EXPENSE') ? 'debit' : 'credit',
        'parent_id': parentId,
        'is_active': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      });
      codeToId[actualCode] = id;
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
      try { await db.execute('ALTER TABLE invoices ADD COLUMN payment_mechanism TEXT NOT NULL DEFAULT \'cash\''); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN payment_method TEXT NOT NULL DEFAULT \'cash\''); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN is_return INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN cash_box_id INTEGER'); } catch (e) { logMigrationError("migration", e); }

      // Add balance_type to customers
      try { await db.execute('ALTER TABLE customers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\''); } catch (e) { logMigrationError("migration", e); }

      // Add balance_type to suppliers (default 'credit' because we typically owe the supplier)
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\''); } catch (e) { logMigrationError("migration", e); }

      // Add linked_cash_box_id to accounts
      try { await db.execute('ALTER TABLE accounts ADD COLUMN linked_cash_box_id INTEGER'); } catch (e) { logMigrationError("migration", e); }

      // Change currency default in accounts
      try { await db.execute('UPDATE accounts SET currency = \'YER\' WHERE currency = \'SAR\''); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('UPDATE suppliers SET currency = \'YER\' WHERE currency = \'SAR\''); } catch (e) { logMigrationError("migration", e); }

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
      } catch (e) { logMigrationError("migration", e); }

      // Update default VAT rate
      try { await db.execute('UPDATE products SET tax_rate = 0.0 WHERE tax_rate = 15.0'); } catch (e) { logMigrationError("migration", e); }

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
      } catch (e) { logMigrationError("migration", e); }
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
      try { await db.execute('ALTER TABLE invoices ADD COLUMN currency TEXT NOT NULL DEFAULT \'YER\''); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0'); } catch (e) { logMigrationError("migration", e); }

      // Add currency column to customers
      try { await db.execute('ALTER TABLE customers ADD COLUMN currency TEXT NOT NULL DEFAULT \'YER\''); } catch (e) { logMigrationError("migration", e); }
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
      try { await db.execute('ALTER TABLE invoices ADD COLUMN transport_charges REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }

      // Delete AED and KWD currencies
      try { await db.delete('currencies', where: 'code IN (?, ?)', whereArgs: ['AED', 'KWD']); } catch (e) { logMigrationError("migration", e); }

      // Seed accounts for SAR and USD currencies if they don't exist
      await _seedAccountsForCurrency(db, 'YER', 'ر.ي', 0);
      await _seedAccountsForCurrency(db, 'SAR', 'ر.س', 1);
      await _seedAccountsForCurrency(db, 'USD', r'$', 2);
    }
    if (oldVersion < 7) {
      // Add e-wallet and bank transfer columns to invoices
      try { await db.execute('ALTER TABLE invoices ADD COLUMN ewallet_provider TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN bank_transfer_provider TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN transfer_number TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN attachment_path TEXT'); } catch (e) { logMigrationError("migration", e); }
    }
    if (oldVersion < 8) {
      // Add debt_ceiling and balance_type to accounts
      try { await db.execute('ALTER TABLE accounts ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE accounts ADD COLUMN balance_type TEXT NOT NULL DEFAULT \'credit\''); } catch (e) { logMigrationError("migration", e); }

      // Add attachment_path, operation_type, expense_account_id to expenses
      try { await db.execute('ALTER TABLE expenses ADD COLUMN attachment_path TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE expenses ADD COLUMN operation_type TEXT NOT NULL DEFAULT \'صرف\''); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE expenses ADD COLUMN expense_account_id INTEGER'); } catch (e) { logMigrationError("migration", e); }

      // Add index for expense_account_id
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_expense_account_id ON expenses (expense_account_id)'); } catch (e) { logMigrationError("migration", e); }
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
        } catch (e) { logMigrationError("migration", e); }
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
      try { await db.execute('ALTER TABLE invoices ADD COLUMN shift_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN cashier_name TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoices ADD COLUMN is_posted INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }

      // Create indexes for new invoice columns
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_shift_id ON invoices (shift_id)'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_is_posted ON invoices (is_posted)'); } catch (e) { logMigrationError("migration", e); }

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
      } catch (e) { logMigrationError("migration", e); }
    }

    // ══════════════════════════════════════════════════════════════
    //  v13 Migration: add currency column to cash_boxes, cashier_name to shifts
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 13) {
      // Add currency column to cash_boxes
      try { await db.execute("ALTER TABLE cash_boxes ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'"); } catch (e) { logMigrationError("migration", e); }

      // Add cashier_name column to shifts
      try { await db.execute("ALTER TABLE shifts ADD COLUMN cashier_name TEXT"); } catch (e) { logMigrationError("migration", e); }
    }
    if (oldVersion < 14) {
      // Add image_path column to products
      try { await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT'); } catch (e) { logMigrationError("migration", e); }
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
      try { await db.execute("ALTER TABLE cash_boxes ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'"); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE shifts ADD COLUMN cashier_name TEXT'); } catch (e) { logMigrationError("migration", e); }
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
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }

      // Add contact_method column to suppliers
      try { await db.execute("ALTER TABLE suppliers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { logMigrationError("migration", e); }

      // Fix supplier balance_type default to 'credit' (we typically owe the supplier)
      try { await db.execute("UPDATE suppliers SET balance_type = 'credit' WHERE balance_type = 'debit' AND balance >= 0"); } catch (e) { logMigrationError("migration", e); }

      // Add customer_id and supplier_id columns to vouchers
      try { await db.execute('ALTER TABLE vouchers ADD COLUMN customer_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE vouchers ADD COLUMN supplier_id INTEGER'); } catch (e) { logMigrationError("migration", e); }

      // Seed new accounts for each currency if they don't exist
      final now20 = DateTime.now().toIso8601String();
      final newAccountTemplates = [
        // Inventory account (ASSET, code 1300+offset)
        {'baseCode': 1300, 'nameAr': 'المخزون', 'nameEn': 'Inventory Account', 'type': 'ASSET'},
        // Opening Balance Equity (EQUITY, code 2901+offset) — P-04: was LIABILITY, now EQUITY; v43: code moved from 2200 to 2901
        {'baseCode': 2901, 'nameAr': 'رصيد افتتاحي', 'nameEn': 'Opening Balance Equity', 'type': 'EQUITY'},
        // Retained Earnings (EQUITY, code 2900+offset) — P-04: was LIABILITY, now EQUITY
        {'baseCode': 2900, 'nameAr': 'الأرباح المحتجزة', 'nameEn': 'Retained Earnings', 'type': 'EQUITY'},
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

    // ══════════════════════════════════════════════════════════════
    //  v21 Migration: Add contact_method and debt_ceiling to customers
    //  (replacing notification_method and credit_limit fields)
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 21) {
      // Add contact_method column to customers (replacing notification_method)
      try { await db.execute("ALTER TABLE customers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { logMigrationError("migration", e); }

      // Add debt_ceiling column to customers (replacing credit_limit)
      try { await db.execute('ALTER TABLE customers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }

      // Copy data from old columns to new columns
      try { await db.execute("UPDATE customers SET contact_method = COALESCE(notification_method, 'whatsapp') WHERE contact_method IS NULL OR contact_method = 'whatsapp'"); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('UPDATE customers SET debt_ceiling = COALESCE(credit_limit, 0.0) WHERE debt_ceiling = 0.0'); } catch (e) { logMigrationError("migration", e); }
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
      } catch (e) { logMigrationError("migration", e); }
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
      try { await db.execute('ALTER TABLE products ADD COLUMN base_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN purchase_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sale_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN tax_inclusive INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN allow_negative INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sell_retail INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN show_in_pos INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT'); } catch (e) { logMigrationError("migration", e); }

      // Migrate existing unit_id → base_unit_id
      await db.execute('UPDATE products SET base_unit_id = unit_id WHERE base_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET sale_unit_id = unit_id WHERE sale_unit_id IS NULL AND unit_id IS NOT NULL');
      await db.execute('UPDATE products SET purchase_unit_id = unit_id WHERE purchase_unit_id IS NULL AND unit_id IS NOT NULL');

      // ── Add unit fields to invoice_items ──
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_name TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1.0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN base_quantity REAL NOT NULL DEFAULT 1.0'); } catch (e) { logMigrationError("migration", e); }

      // Backfill base_quantity from quantity for existing invoice items
      await db.execute('UPDATE invoice_items SET base_quantity = quantity WHERE base_quantity = 1.0 AND quantity != 1.0');

      // ── Update unit_conversions to use unit IDs ──
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN from_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN to_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
    }

    // ══════════════════════════════════════════════════════════════
    //  v26 Migration: Ensure ALL missing columns exist (fixes databases
    //  created with broken _onCreate that lacked average_cost etc.)
    //  Also adds VAT account (code 3300) for each currency.
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 26) {
      // ── Products table: add missing columns ──
      try { await db.execute('ALTER TABLE products ADD COLUMN average_cost REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN tax_inclusive INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN expiry_tracking INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN has_variants INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN base_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN purchase_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sale_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN allow_negative INTEGER NOT NULL DEFAULT 0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN sell_retail INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN show_in_pos INTEGER NOT NULL DEFAULT 1'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT'); } catch (e) { logMigrationError("migration", e); }

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
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_name TEXT'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1.0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE invoice_items ADD COLUMN base_quantity REAL NOT NULL DEFAULT 1.0'); } catch (e) { logMigrationError("migration", e); }

      // ── Add debt_ceiling and contact_method to customers ──
      try { await db.execute('ALTER TABLE customers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute("ALTER TABLE customers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { logMigrationError("migration", e); }

      // ── Add debt_ceiling and contact_method to suppliers ──
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN debt_ceiling REAL NOT NULL DEFAULT 0.0'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute("ALTER TABLE suppliers ADD COLUMN contact_method TEXT DEFAULT 'whatsapp'"); } catch (e) { logMigrationError("migration", e); }

      // ── Add operation_type and expense_account_id to expenses ──
      try { await db.execute("ALTER TABLE expenses ADD COLUMN operation_type TEXT NOT NULL DEFAULT 'صرف'"); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE expenses ADD COLUMN expense_account_id INTEGER'); } catch (e) { logMigrationError("migration", e); }

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

    // ══════════════════════════════════════════════════════════════
    //  v27 Migration: Add cogs_account_id and vat_account_id to products
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 27) {
      try { await db.execute('ALTER TABLE products ADD COLUMN cogs_account_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE products ADD COLUMN vat_account_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
    }

    // ══════════════════════════════════════════════════════════════
    //  v28 Migration: Ensure from_unit_id and to_unit_id exist in unit_conversions
    //  (was missing from _onCreate in earlier versions)
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 28) {
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN from_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
      try { await db.execute('ALTER TABLE unit_conversions ADD COLUMN to_unit_id INTEGER'); } catch (e) { logMigrationError("migration", e); }
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
      } catch (e) { logMigrationError("migration", e); }
    }
    if (oldVersion < 31) {
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN original_invoice_id TEXT');
      } catch (e) { logMigrationError("migration", e); }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_original ON invoices (original_invoice_id)');
    }

    // v32: Ensure stock_movements and unit_conversions tables exist, add cost_price column
    if (oldVersion < 32) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_ref ON stock_movements (reference_type, reference_id)');

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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unit_conversions_product ON unit_conversions (product_id)');

      // Add cost_price column to unit_conversions if it doesn't exist
      try {
        await db.execute('ALTER TABLE unit_conversions ADD COLUMN cost_price REAL NOT NULL DEFAULT 0.0');
      } catch (e) { logMigrationError("alter", e);
        // Column already exists, ignore
      }
    }

    // v33: Add held_orders table for POS held orders persistence
    if (oldVersion < 33) {
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
      await db.execute('CREATE INDEX IF NOT EXISTS idx_held_orders_shift ON held_orders (shift_id)');
    }

    // ══════════════════════════════════════════════════════════════
    //  v34 Migration: Convert REAL monetary columns to INTEGER (cents)
    //  C-06: Store money as integer cents for precision
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 34) {
      await _migrateV34RealToInteger(db);
      // M-05: Add unique constraint on (account_code, currency)
      try { await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_code_currency ON accounts (account_code, currency)'); } catch (e) { logMigrationError("migration", e); }
    }

    // ══════════════════════════════════════════════════════════════
    //  v35 Migration: Fix EXPENSE balance_type + Add EQUITY type
    //  ── EXPENSE accounts should be debit-nature, not credit
    //  ── Add EQUITY account type (حقوق الملكية) separate from LIABILITY
    //  ── Move Opening Balance Equity & Retained Earnings to EQUITY
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 35) {
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
        final totalDebit = MoneyHelper.readCalculatedMoney(txResult.first['total_debit']);
        final totalCredit = MoneyHelper.readCalculatedMoney(txResult.first['total_credit']);
        // EXPENSE is debit-nature: balance = debit - credit
        final correctBalance = totalDebit - totalCredit;
        await db.update(
          'accounts',
          {'balance': MoneyHelper.toCents(correctBalance), 'updated_at': DateTime.now().toIso8601String()},
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
        final totalDebit = MoneyHelper.readCalculatedMoney(txResult.first['total_debit']);
        final totalCredit = MoneyHelper.readCalculatedMoney(txResult.first['total_credit']);
        // EQUITY is credit-nature: balance = credit - debit
        final correctBalance = totalCredit - totalDebit;
        await db.update(
          'accounts',
          {'balance': MoneyHelper.toCents(correctBalance), 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v36: P-06 — Add unit_cost column to invoice_items
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 36) {
      // Add unit_cost column for accurate COGS on deferred POS posting
      await db.execute('ALTER TABLE invoice_items ADD COLUMN unit_cost INTEGER NOT NULL DEFAULT 0');
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v37: Add currency column to products table
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 37) {
      try {
        await db.execute("ALTER TABLE products ADD COLUMN currency TEXT NOT NULL DEFAULT 'YER'");
      } catch (e) {
        logMigrationError("migration", e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v38: FIFO/LIFO costing + Bank Reconciliation
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 38) {
      // 1A: Add costing_method to products
      try {
        await db.execute("ALTER TABLE products ADD COLUMN costing_method TEXT NOT NULL DEFAULT 'weighted_average'");
      } catch (e) {
        logMigrationError("migration v38 costing_method", e);
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
        await db.execute('CREATE INDEX IF NOT EXISTS idx_cost_layers_product ON inventory_cost_layers (product_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_cost_layers_fifo ON inventory_cost_layers (product_id, acquisition_date, quantity_remaining) WHERE is_fully_consumed = 0');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_cost_layers_consumed ON inventory_cost_layers (is_fully_consumed)');
      } catch (e) {
        logMigrationError("migration v38 inventory_cost_layers", e);
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
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mca_product ON movement_cost_allocations (product_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mca_layer ON movement_cost_allocations (cost_layer_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mca_invoice ON movement_cost_allocations (invoice_id)');
      } catch (e) {
        logMigrationError("migration v38 movement_cost_allocations", e);
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
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_recon_cash_box ON bank_reconciliations (cash_box_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_recon_status ON bank_reconciliations (status)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_recon_number ON bank_reconciliations (reconciliation_number)');
      } catch (e) {
        logMigrationError("migration v38 bank_reconciliations", e);
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
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_stmt_recon ON bank_statement_lines (reconciliation_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_stmt_cash_box ON bank_statement_lines (cash_box_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_stmt_status ON bank_statement_lines (match_status)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_bank_stmt_date ON bank_statement_lines (transaction_date)');
      } catch (e) {
        logMigrationError("migration v38 bank_statement_lines", e);
      }

      // Initialize cost layers for existing products
      try {
        final costingEngine = CostingEngineService(this);
        await costingEngine.initializeCostLayersForExistingProducts();
      } catch (e) {
        logMigrationError("migration v38 init_cost_layers", e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v39: Fix balance_type for all accounts
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 39) {
      await _migrateV39(db);
    }

    // ── v40: C-05 + C-07: Add UNIQUE constraint on invoice numbers, add balance_type to transactions ──
    if (oldVersion < 40) {
      try {
        // C-05: Add UNIQUE index on invoice id to prevent duplicates
        // Since id is already PRIMARY KEY, we add a UNIQUE index on a composite to catch duplicates
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_unique_id ON invoices(id)');
        
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
        logMigrationError('v40', e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v41: Accounting tree hierarchy + code corrections
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 41) {
      try {
        await _migrateV41(db);
      } catch (e) {
        logMigrationError('v41', e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v42: Fix account codes and hierarchy
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 42) {
      try {
        await _migrateV42(db);
      } catch (e) {
        logMigrationError('v42', e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    //  Migration v43: Rename Opening Balance Equity code 2200→2901
    // ══════════════════════════════════════════════════════════════
    if (oldVersion < 43) {
      try {
        await _migrateV43(db);
      } catch (e) {
        logMigrationError('v43', e);
      }
    }
  }

  /// Migration v42: Fix account codes and hierarchy for dynamically created accounts
  /// - Rename exchange gains account from 5310 to 4700 (proper REVENUE range)
  /// - Rename discount allowed from 4500 to 5400 (proper EXPENSE range)
  /// - Set parent_id for orphaned dynamic accounts
  Future<void> _migrateV42(Database db) async {
    final now = DateTime.now().toIso8601String();

    // 1. Rename exchange gains account code 5310 → 4700
    try {
      final oldGainRows = await db.query('accounts', where: 'account_code = ?', whereArgs: ['5310']);
      for (final row in oldGainRows) {
        final newCodeExists = await db.query('accounts', where: 'account_code = ?', whereArgs: ['4700'], limit: 1);
        if (newCodeExists.isEmpty) {
          await db.update('accounts', {'account_code': '4700', 'updated_at': now}, where: 'id = ?', whereArgs: [row['id']]);
        }
      }
    } catch (e) { logMigrationError('v42_exchange_gains', e); }

    // 2. Rename discount allowed account code 4500 → 5400
    try {
      final oldDiscountRows = await db.query('accounts', where: 'account_code = ?', whereArgs: ['4500']);
      for (final row in oldDiscountRows) {
        final newCodeExists = await db.query('accounts', where: 'account_code = ?', whereArgs: ['5400'], limit: 1);
        if (newCodeExists.isEmpty) {
          await db.update('accounts', {'account_code': '5400', 'updated_at': now}, where: 'id = ?', whereArgs: [row['id']]);
        }
      }
    } catch (e) { logMigrationError('v42_discount_code', e); }

    // 3. Set parent_id for orphaned dynamic accounts (5250, 5300, 5400 → parent 5000)
    try {
      final expenseRoot = await db.query('accounts', where: 'account_code = ? AND account_type = ?', whereArgs: ['5000', 'EXPENSE'], limit: 1);
      if (expenseRoot.isNotEmpty) {
        final expenseParentId = expenseRoot.first['id'];
        final orphanCodes = ['5250', '5300', '5400'];
        for (final code in orphanCodes) {
          await db.update('accounts', {'parent_id': expenseParentId, 'updated_at': now},
            where: 'account_code = ? AND parent_id IS NULL AND account_type = ?', whereArgs: [code, 'EXPENSE']);
        }
      }
    } catch (e) { logMigrationError('v42_expense_parent', e); }

    // 4. Set parent_id for revenue dynamic accounts (4600, 4700 → parent 4000)
    try {
      final revenueRoot = await db.query('accounts', where: 'account_code = ? AND account_type = ?', whereArgs: ['4000', 'REVENUE'], limit: 1);
      if (revenueRoot.isNotEmpty) {
        final revenueParentId = revenueRoot.first['id'];
        final orphanCodes = ['4600', '4700'];
        for (final code in orphanCodes) {
          await db.update('accounts', {'parent_id': revenueParentId, 'updated_at': now},
            where: 'account_code = ? AND parent_id IS NULL AND account_type = ?', whereArgs: [code, 'REVENUE']);
        }
      }
    } catch (e) { logMigrationError('v42_revenue_parent', e); }

    // 5. Seed missing accounts from updated templates (4600, 4700, 5250, 5300, 5400)
    try {
      await _seedDefaultAccounts(db);
    } catch (e) { logMigrationError('v42_seed_accounts', e); }
  }

  /// Migration v43: Fix chart of accounts code conflicts and hierarchy
  /// 1. Rename Opening Balance Equity account code from 2200→2901
  ///    (move from LIABILITY range to EQUITY sub-range)
  /// 2. Rename Inventory Variance Loss account code from 5400→5500
  ///    (5400 conflicts with Discount Allowed)
  /// 3. Seed new accounts (5500 variance loss, 4400 variance income)
  /// Applies to all 3 currency offsets: YER(0), SAR(1), USD(2).
  Future<void> _migrateV43(Database db) async {
    final now = DateTime.now().toIso8601String();
    final codeOffsets = [0, 1, 2]; // YER, SAR, USD

    // ── Step 1: Rename Opening Balance Equity 2200 → 2901 ──
    for (final offset in codeOffsets) {
      final oldCode = (2200 + offset).toString();
      final newCode = (2901 + offset).toString();

      try {
        final oldRows = await db.query('accounts', where: 'account_code = ?', whereArgs: [oldCode]);
        for (final row in oldRows) {
          final currency = row['currency'] as String? ?? 'YER';
          final newCodeExists = await db.query('accounts',
              where: 'account_code = ? AND currency = ?', whereArgs: [newCode, currency], limit: 1);

          if (newCodeExists.isEmpty) {
            await db.update('accounts',
                {'account_code': newCode, 'updated_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          } else {
            final oldAccountId = row['id'] as int;
            final newAccountId = newCodeExists.first['id'] as int;
            await db.update('transactions',
                {'account_id': newAccountId},
                where: 'account_id = ?', whereArgs: [oldAccountId]);
            await db.delete('accounts', where: 'id = ?', whereArgs: [oldAccountId]);
          }
        }
      } catch (e) { logMigrationError('v43_rename_2200_$offset', e); }
    }

    // ── Step 2: Rename Inventory Variance Loss 5400 → 5500 ──
    // Only rename EXPENSE accounts at code 5400 that are "خسارة تفاوت الجرد"
    // (do NOT touch "خصم مسموح به" / Discount Allowed which is the correct 5400)
    for (final offset in codeOffsets) {
      final oldCode = (5400 + offset).toString();
      final newCode = (5500 + offset).toString();

      try {
        final oldRows = await db.query('accounts',
            where: "account_code = ? AND (name_ar LIKE '%تفاوت%' OR name_en LIKE '%Variance%')",
            whereArgs: [oldCode]);
        for (final row in oldRows) {
          final currency = row['currency'] as String? ?? 'YER';
          final newCodeExists = await db.query('accounts',
              where: 'account_code = ? AND currency = ?', whereArgs: [newCode, currency], limit: 1);

          if (newCodeExists.isEmpty) {
            await db.update('accounts',
                {'account_code': newCode, 'updated_at': now},
                where: 'id = ?', whereArgs: [row['id']]);
          } else {
            final oldAccountId = row['id'] as int;
            final newAccountId = newCodeExists.first['id'] as int;
            await db.update('transactions',
                {'account_id': newAccountId},
                where: 'account_id = ?', whereArgs: [oldAccountId]);
            await db.delete('accounts', where: 'id = ?', whereArgs: [oldAccountId]);
          }
        }
      } catch (e) { logMigrationError('v43_rename_variance_5400_$offset', e); }
    }

    // ── Step 3: Seed new/missing accounts from updated templates ──
    try {
      await _seedDefaultAccounts(db);
    } catch (e) { logMigrationError('v43_seed_accounts', e); }
  }

  /// Migration v39: Fix #9 — Set correct balance_type for existing accounts
  /// and ensure default accounts have the right balance_type.
  ///
  /// ASSET, EXPENSE → 'debit' (increase on debit side)
  /// LIABILITY, REVENUE, EQUITY → 'credit' (increase on credit side)
  Future<void> _migrateV39(Database db) async {
    await db.transaction((txn) async {
      // Fix balance_type for ASSET accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('ASSET') AND balance_type != 'debit'",
        );
      } catch (e) {
        logMigrationError("migration v39 fix_asset_balance_type", e);
      }

      // Fix balance_type for EXPENSE accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'debit' WHERE account_type IN ('EXPENSE') AND balance_type != 'debit'",
        );
      } catch (e) {
        logMigrationError("migration v39 fix_expense_balance_type", e);
      }

      // Fix balance_type for LIABILITY accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('LIABILITY') AND balance_type != 'credit'",
        );
      } catch (e) {
        logMigrationError("migration v39 fix_liability_balance_type", e);
      }

      // Fix balance_type for REVENUE accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('REVENUE') AND balance_type != 'credit'",
        );
      } catch (e) {
        logMigrationError("migration v39 fix_revenue_balance_type", e);
      }

      // Fix balance_type for EQUITY accounts
      try {
        await txn.execute(
          "UPDATE accounts SET balance_type = 'credit' WHERE account_type IN ('EQUITY') AND balance_type != 'credit'",
        );
      } catch (e) {
        logMigrationError("migration v39 fix_equity_balance_type", e);
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
        logMigrationError("migration v39 fix_exchange_account", e);
      }
    });
  }

  /// Migration v41: Accounting tree hierarchy — set parent_id for existing accounts,
  /// rename VAT account from 3300 to 2300 (proper LIABILITY range), and add group accounts.
  Future<void> _migrateV41(Database db) async {
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
          where: 'account_code = ? AND currency = ?', whereArgs: [oldVatCode, currency]);
      if (vatRows.isNotEmpty) {
        // Check if new code already exists
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?', whereArgs: [newVatCode, currency]);
        if (newCodeExists.isEmpty) {
          await db.update('accounts',
              {'account_code': newVatCode, 'updated_at': now},
              where: 'id = ?', whereArgs: [vatRows.first['id']]);
        }
      }

      // ── 2. Rename Retained Earnings from 2900+offset → 2910+offset ──
      // (2900 becomes the Equity parent group account)
      final oldRetainedCode = (2900 + offset).toString();
      final newRetainedCode = (2910 + offset).toString();
      final retainedRows = await db.query('accounts',
          where: 'account_code = ? AND currency = ?', whereArgs: [oldRetainedCode, currency]);
      if (retainedRows.isNotEmpty) {
        final newCodeExists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?', whereArgs: [newRetainedCode, currency]);
        if (newCodeExists.isEmpty) {
          await db.update('accounts',
              {'account_code': newRetainedCode, 'updated_at': now},
              where: 'id = ?', whereArgs: [retainedRows.first['id']]);
        }
      }

      // ── 3. Add missing group/parent accounts if they don't exist ──
      final groupAccounts = [
        {'code': (2000 + offset).toString(), 'name_ar': 'حساب الخصوم', 'name_en': 'Liabilities Account', 'type': 'LIABILITY'},
        {'code': (2900 + offset).toString(), 'name_ar': 'حقوق الملكية', 'name_en': 'Equity Account', 'type': 'EQUITY'},
        {'code': (3000 + offset).toString(), 'name_ar': 'حساب التكاليف', 'name_en': 'Cost Account', 'type': 'COST'},
        {'code': (4000 + offset).toString(), 'name_ar': 'حساب الإيرادات', 'name_en': 'Revenue Account', 'type': 'REVENUE'},
      ];
      for (final group in groupAccounts) {
        final exists = await db.query('accounts',
            where: 'account_code = ? AND currency = ?',
            whereArgs: [group['code'], currency]);
        if (exists.isEmpty) {
          await db.insert('accounts', {
            'name_ar': '${group['name_ar']} (${currency == 'YER' ? 'ر.ي' : currency == 'SAR' ? 'ر.س' : r'$'})',
            'name_en': '${group['name_en']} ($currency)',
            'account_code': group['code'],
            'account_type': group['type'],
            'balance': 0,
            'currency': currency,
            'balance_type': (group['type'] == 'ASSET' || group['type'] == 'COST' || group['type'] == 'EXPENSE') ? 'debit' : 'credit',
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
        (1100 + offset).toString(): (1000 + offset).toString(), // Cash&Banks → Assets
        (1200 + offset).toString(): (1000 + offset).toString(), // Customers → Assets
        (1300 + offset).toString(): (1000 + offset).toString(), // Inventory → Assets
        (2100 + offset).toString(): (2000 + offset).toString(), // Suppliers → Liabilities
        (2300 + offset).toString(): (2000 + offset).toString(), // VAT → Liabilities (new code)
        (2901 + offset).toString(): (2900 + offset).toString(), // Opening Balance → Equity
        (2910 + offset).toString(): (2900 + offset).toString(), // Retained Earnings → Equity (new code)
        (3100 + offset).toString(): (3000 + offset).toString(), // Purchases → Costs
        (3200 + offset).toString(): (3000 + offset).toString(), // COGS → Costs
        (4100 + offset).toString(): (4000 + offset).toString(), // Sales → Revenue
        (4400 + offset).toString(): (4000 + offset).toString(), // Variance Income → Revenue
        (5100 + offset).toString(): (5000 + offset).toString(), // Employees → Expenses
        (5200 + offset).toString(): (5000 + offset).toString(), // Transport → Expenses
        (5250 + offset).toString(): (5000 + offset).toString(), // Bank Charges → Expenses
        (5500 + offset).toString(): (5000 + offset).toString(), // Variance Loss → Expenses
      };

      for (final entry in parentMappings.entries) {
        final childCode = entry.key;
        final parentCode = entry.value;
        final childRows = await db.query('accounts',
            where: 'account_code = ? AND currency = ?', whereArgs: [childCode, currency]);
        final parentRows = await db.query('accounts',
            where: 'account_code = ? AND currency = ?', whereArgs: [parentCode, currency]);
        if (childRows.isNotEmpty && parentRows.isNotEmpty) {
          final parentId = parentRows.first['id'];
          await db.update('accounts',
              {'parent_id': parentId, 'updated_at': now},
              where: 'id = ?', whereArgs: [childRows.first['id']]);
        }
      }
    }
  }

  /// C-06: Migrate all REAL monetary columns to INTEGER (cents).
  ///
  /// SQLite does not support ALTER COLUMN, so we must use the
  /// table rebuild pattern for each affected table:
  ///   1. CREATE TABLE temp_xxx with INTEGER columns
  ///   2. INSERT INTO temp SELECT ... with CAST(ROUND(col*100) AS INTEGER) for money
  ///   3. DROP TABLE xxx
  ///   4. ALTER TABLE temp_xxx RENAME TO xxx
  ///   5. Recreate indexes
  Future<void> _migrateV34RealToInteger(Database db) async {
    // Helper: money columns use CAST(ROUND(col*100) AS INTEGER)
    // Non-money REAL columns (quantities, rates) copy as-is.
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
      await txn.execute('CREATE INDEX idx_accounts_account_code ON accounts (account_code)');
      await txn.execute('CREATE INDEX idx_accounts_account_type ON accounts (account_type)');

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
      await txn.execute('CREATE INDEX idx_products_barcode ON products (barcode)');
      await txn.execute('CREATE INDEX idx_products_item_code ON products (item_code)');
      await txn.execute('CREATE INDEX idx_products_category_id ON products (category_id)');

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
      await txn.execute('CREATE INDEX idx_invoices_customer_id ON invoices (customer_id)');
      await txn.execute('CREATE INDEX idx_invoices_created_at ON invoices (created_at)');
      await txn.execute('CREATE INDEX idx_invoices_status ON invoices (status)');
      await txn.execute('CREATE INDEX idx_invoices_shift_id ON invoices (shift_id)');
      await txn.execute('CREATE INDEX idx_invoices_is_posted ON invoices (is_posted)');
      await txn.execute('CREATE INDEX IF NOT EXISTS idx_invoices_original ON invoices (original_invoice_id)');

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
      await txn.execute('ALTER TABLE temp_invoice_items RENAME TO invoice_items');
      await txn.execute('CREATE INDEX idx_invoice_items_invoice_id ON invoice_items (invoice_id)');

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
      await txn.execute('CREATE INDEX idx_transactions_account_id ON transactions (account_id)');
      await txn.execute('CREATE INDEX idx_transactions_journal_id ON transactions (journal_id)');
      await txn.execute('CREATE INDEX idx_transactions_date ON transactions (date)');

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
      await txn.execute('CREATE INDEX idx_cash_boxes_type ON cash_boxes (type)');

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
      await txn.execute('CREATE INDEX idx_expenses_category ON expenses (category)');
      await txn.execute('CREATE INDEX idx_expenses_expense_date ON expenses (expense_date)');
      await txn.execute('CREATE INDEX idx_expenses_account_id ON expenses (account_id)');
      await txn.execute('CREATE INDEX idx_expenses_expense_account_id ON expenses (expense_account_id)');

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
      await txn.execute('CREATE INDEX idx_employees_is_active ON employees (is_active)');

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
      await txn.execute('CREATE INDEX idx_quotations_customer_id ON quotations (customer_id)');
      await txn.execute('CREATE INDEX idx_quotations_status ON quotations (status)');

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
      await txn.execute('ALTER TABLE temp_quotation_items RENAME TO quotation_items');
      await txn.execute('CREATE INDEX idx_quotation_items_quotation_id ON quotation_items (quotation_id)');

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
      await txn.execute('ALTER TABLE temp_purchase_orders RENAME TO purchase_orders');
      await txn.execute('CREATE INDEX idx_purchase_orders_supplier_id ON purchase_orders (supplier_id)');
      await txn.execute('CREATE INDEX idx_purchase_orders_status ON purchase_orders (status)');

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
      await txn.execute('ALTER TABLE temp_purchase_order_items RENAME TO purchase_order_items');
      await txn.execute('CREATE INDEX idx_purchase_order_items_po_id ON purchase_order_items (purchase_order_id)');

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
      await txn.execute('CREATE INDEX idx_sales_orders_customer_id ON sales_orders (customer_id)');
      await txn.execute('CREATE INDEX idx_sales_orders_status ON sales_orders (status)');

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
      await txn.execute('ALTER TABLE temp_sales_order_items RENAME TO sales_order_items');
      await txn.execute('CREATE INDEX idx_sales_order_items_so_id ON sales_order_items (sales_order_id)');

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
      await txn.execute('CREATE INDEX idx_shifts_cashier_id ON shifts (cashier_id)');
      await txn.execute('CREATE INDEX idx_shifts_cash_box_id ON shifts (cash_box_id)');
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
      await txn.execute('ALTER TABLE temp_currency_exchanges RENAME TO currency_exchanges');
      await txn.execute('CREATE INDEX idx_currency_exchanges_number ON currency_exchanges (exchange_number)');
      await txn.execute('CREATE INDEX idx_currency_exchanges_created_at ON currency_exchanges (created_at)');

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
      await txn.execute('ALTER TABLE temp_cash_transfers RENAME TO cash_transfers');
      await txn.execute('CREATE INDEX idx_cash_transfers_number ON cash_transfers (transfer_number)');
      await txn.execute('CREATE INDEX idx_cash_transfers_created_at ON cash_transfers (created_at)');

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
      await txn.execute('CREATE INDEX idx_vouchers_voucher_number ON vouchers (voucher_number)');
      await txn.execute('CREATE INDEX idx_vouchers_voucher_type ON vouchers (voucher_type)');
      await txn.execute('CREATE INDEX idx_vouchers_date ON vouchers (date)');
      await txn.execute('CREATE INDEX idx_vouchers_created_at ON vouchers (created_at)');

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
      await txn.execute('ALTER TABLE temp_voucher_items RENAME TO voucher_items');
      await txn.execute('CREATE INDEX idx_voucher_items_voucher_id ON voucher_items (voucher_id)');
      await txn.execute('CREATE INDEX idx_voucher_items_account_id ON voucher_items (account_id)');

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
      await txn.execute('ALTER TABLE temp_inventory_vouchers RENAME TO inventory_vouchers');
      await txn.execute('CREATE INDEX idx_inventory_vouchers_number ON inventory_vouchers (voucher_number)');
      await txn.execute('CREATE INDEX idx_inventory_vouchers_date ON inventory_vouchers (date)');
      await txn.execute('CREATE INDEX idx_inventory_vouchers_warehouse ON inventory_vouchers (warehouse_id)');
      await txn.execute('CREATE INDEX idx_inventory_vouchers_status ON inventory_vouchers (status)');

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
      await txn.execute('ALTER TABLE temp_inventory_voucher_items RENAME TO inventory_voucher_items');
      await txn.execute('CREATE INDEX idx_inventory_voucher_items_voucher ON inventory_voucher_items (voucher_id)');
      await txn.execute('CREATE INDEX idx_inventory_voucher_items_product ON inventory_voucher_items (product_id)');

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
      await txn.execute('CREATE INDEX idx_fiscal_years_year ON fiscal_years (year)');
      await txn.execute('CREATE INDEX idx_fiscal_years_status ON fiscal_years (status)');

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
      await txn.execute('ALTER TABLE temp_unit_conversions RENAME TO unit_conversions');
      await txn.execute('CREATE INDEX idx_unit_conversions_product ON unit_conversions (product_id)');

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
      await txn.execute('ALTER TABLE temp_stock_movements RENAME TO stock_movements');
      await txn.execute('CREATE INDEX idx_stock_movements_product ON stock_movements (product_id)');
      await txn.execute('CREATE INDEX idx_stock_movements_type ON stock_movements (movement_type)');
      await txn.execute('CREATE INDEX idx_stock_movements_ref ON stock_movements (reference_type, reference_id)');

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
      await txn.execute('CREATE INDEX idx_held_orders_shift ON held_orders (shift_id)');
    });
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

  /// Delegates to [JournalService.updateAccountBalance].
  Future<void> updateAccountBalance(int accountId, double amount, {required bool isDebit}) =>
      journal.updateAccountBalance(accountId, amount, isDebit: isDebit);

  /// Update an account's balance considering its balance_type.
  /// For credit-balance accounts (LIABILITY, REVENUE, most EXPENSE):
  ///   balance = balance + credit - debit
  /// For debit-balance accounts (ASSET, COST):
  ///   balance = balance + debit - credit
  /// Validate that total debits equal total credits for a journal entry (C-03)
  /// Throws an exception if the journal entry is unbalanced.
  void _validateJournalBalance(List<Map<String, dynamic>> entries) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final entry in entries) {
      totalDebit += MoneyHelper.readMoney(entry['debit']);
      totalCredit += MoneyHelper.readMoney(entry['credit']);
    }
    final difference = (totalDebit - totalCredit).abs();
    if (difference > 0.01) {
      debugPrint('⚠️ UNBALANCED JOURNAL ENTRY: Debit=$totalDebit, Credit=$totalCredit, Diff=$difference');
      throw Exception('قيد محاسبي غير متوازن: المدين=$totalDebit, الدائن=$totalCredit, الفرق=$difference');
    }
  }

  Future<void> _updateAccountBalanceWithJournal(
    Transaction txn,
    int accountId,
    double debit,
    double credit,
    String now,
  ) async {
    final account = await txn.query('accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (account.isNotEmpty) {
      final currentBalance = MoneyHelper.readMoney(account.first['balance']);
      final balanceType = account.first['balance_type'] as String? ?? 'credit';
      double newBalance;
      if (balanceType == 'credit') {
        newBalance = currentBalance + credit - debit;
      } else {
        newBalance = currentBalance + debit - credit;
      }
      await txn.update('accounts', {'balance': MoneyHelper.toCents(newBalance), 'updated_at': now}, where: 'id = ?', whereArgs: [accountId]);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Product CRUD methods
  // ══════════════════════════════════════════════════════════════

  Future<int> insertProduct(Map<String, dynamic> productMap) => products.insertProduct(productMap);

  Future<List<Map<String, dynamic>>> getAllProducts({bool? activeOnly, String orderBy = 'created_at DESC', int? limit, int offset = 0}) => products.getAllProducts(activeOnly: activeOnly, orderBy: orderBy, limit: limit, offset: offset);
  Future<List<Product>> getAllProductObjects({bool? activeOnly, String orderBy = 'created_at DESC', int? limit, int offset = 0}) => products.getAllProductObjects(activeOnly: activeOnly, orderBy: orderBy, limit: limit, offset: offset);

  Future<List<Map<String, dynamic>>> searchProducts(String query, {int? warehouseId}) => products.searchProducts(query, warehouseId: warehouseId);
  Future<List<Product>> searchProductObjects(String query, {int? warehouseId}) => products.searchProductObjects(query, warehouseId: warehouseId);

  Future<Map<String, dynamic>?> getProductById(int id) => products.getProductById(id);
  Future<Product?> getProductObjectById(int id) => products.getProductObjectById(id);

  Future<int> updateProduct(int id, Map<String, dynamic> productMap) => products.updateProduct(id, productMap);

  Future<int> deleteProduct(int id) => products.deleteProduct(id);

  Future<void> decrementProductStock(int productId, double quantity) => products.decrementProductStock(productId, quantity);

  /// Increment product stock (used for purchase invoices and sale return restocking).
  Future<void> incrementProductStock(int productId, double quantity) => products.incrementProductStock(productId, quantity);

  Future<int> getProductCount() => products.getProductCount();

  Future<String> getNextItemCode() => products.getNextItemCode();

  /// Check if an item_code already exists in the products table.
  /// Optionally exclude a product ID (for edit mode).
  Future<bool> checkItemCodeExists(String code, {int? excludeId}) => products.checkItemCodeExists(code, excludeId: excludeId);

  /// P-07: Check if a barcode already exists on another product.
  Future<bool> checkBarcodeExists(String barcode, {int? excludeId}) => products.checkBarcodeExists(barcode, excludeId: excludeId);

  // ══════════════════════════════════════════════════════════════
  //  Customer CRUD methods — delegated to CustomerRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCustomer(Map<String, dynamic> customerMap) => customers.insertCustomer(customerMap);
  Future<List<Map<String, dynamic>>> getAllCustomers({String orderBy = 'name', int? limit, int offset = 0}) => customers.getAllCustomers(orderBy: orderBy, limit: limit, offset: offset);
  Future<List<Customer>> getAllCustomerObjects({String orderBy = 'name', int? limit, int offset = 0}) => customers.getAllCustomerObjects(orderBy: orderBy, limit: limit, offset: offset);
  Future<List<Map<String, dynamic>>> searchCustomers(String query) => customers.searchCustomers(query);
  Future<List<Customer>> searchCustomerObjects(String query) => customers.searchCustomerObjects(query);
  Future<Map<String, dynamic>?> getCustomerById(int id) => customers.getCustomerById(id);
  Future<Customer?> getCustomerObjectById(int id) => customers.getCustomerObjectById(id);
  Future<int> updateCustomer(int id, Map<String, dynamic> customerMap) => customers.updateCustomer(id, customerMap);
  Future<int> deleteCustomer(int id) => customers.deleteCustomer(id);
  Future<int> getCustomerCount() => customers.getCustomerCount();
  Future<bool> isCustomerOverDebtCeiling(int customerId, double additionalAmount) => customers.isCustomerOverDebtCeiling(customerId, additionalAmount);
  Future<List<Map<String, dynamic>>> getTopCustomerBalances(int limit) => customers.getTopCustomerBalances(limit);

  // ══════════════════════════════════════════════════════════════
  //  Supplier CRUD methods — delegated to SupplierRepository
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllSuppliers() => suppliers.getAllSuppliers();
  Future<int> insertSupplier(Map<String, dynamic> supplierMap) => suppliers.insertSupplier(supplierMap);
  Future<int> updateSupplier(int id, Map<String, dynamic> supplierMap) => suppliers.updateSupplier(id, supplierMap);
  Future<int> deleteSupplier(int id) => suppliers.deleteSupplier(id);
  Future<List<Map<String, dynamic>>> searchSuppliers(String query) => suppliers.searchSuppliers(query);
  Future<List<Map<String, dynamic>>> getSupplierInvoices(int supplierId) => suppliers.getSupplierInvoices(supplierId);
  Future<List<Map<String, dynamic>>> getSupplierVouchers(int supplierId) => suppliers.getSupplierVouchers(supplierId);
  Future<List<Map<String, dynamic>>> getSupplierMovements(int supplierId) => suppliers.getSupplierMovements(supplierId);
  Future<Map<String, dynamic>?> getSupplierById(int id) => suppliers.getSupplierById(id);
  Future<bool> isSupplierOverDebtCeiling(int supplierId, double additionalAmount) => suppliers.isSupplierOverDebtCeiling(supplierId, additionalAmount);

  // ══════════════════════════════════════════════════════════════
  //  Cash Boxes & Banks CRUD methods — delegated to CashBoxService
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCashBox(Map<String, dynamic> cashBoxMap) => cashBoxes.insertCashBox(cashBoxMap);
  Future<List<Map<String, dynamic>>> getAllCashBoxes() => cashBoxes.getAllCashBoxes();
  Future<List<Map<String, dynamic>>> getCashBoxesByType(String type) => cashBoxes.getCashBoxesByType(type);
  Future<Map<String, dynamic>?> getCashBoxById(int id) => cashBoxes.getCashBoxById(id);
  Future<int> updateCashBox(int id, Map<String, dynamic> cashBoxMap) => cashBoxes.updateCashBox(id, cashBoxMap);
  Future<int> deleteCashBox(int id) => cashBoxes.deleteCashBox(id);
  Future<double> getTotalCashBalance() => cashBoxes.getTotalCashBalance();

  // ══════════════════════════════════════════════════════════════
  //  Currency CRUD methods — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCurrency(Map<String, dynamic> currencyMap) => refData.insertCurrency(currencyMap);
  Future<List<Map<String, dynamic>>> getAllCurrencies({String orderBy = 'is_default DESC, code ASC'}) => refData.getAllCurrencies(orderBy: orderBy);
  Future<Map<String, dynamic>?> getDefaultCurrency() => refData.getDefaultCurrency();
  Future<int> updateCurrency(int id, Map<String, dynamic> currencyMap) => refData.updateCurrency(id, currencyMap);
  Future<int> deleteCurrency(int id) => refData.deleteCurrency(id);
  Future<void> setDefaultCurrency(int id) => refData.setDefaultCurrency(id);

  // ══════════════════════════════════════════════════════════════
  //  Units Master (CRUD) — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertUnit(Map<String, dynamic> unitMap) => refData.insertUnit(unitMap);
  Future<int> updateUnit(int id, Map<String, dynamic> unitMap) => refData.updateUnit(id, unitMap);
  Future<int> deleteUnit(int id) => refData.deleteUnit(id);
  Future<List<Map<String, dynamic>>> getAllUnits({String? unitType, bool activeOnly = false}) => refData.getAllUnits(unitType: unitType, activeOnly: activeOnly);
  Future<Map<String, dynamic>?> getUnitById(int id) => refData.getUnitById(id);
  Future<String> getUnitNameById(int unitId) => refData.getUnitNameById(unitId);

  // ══════════════════════════════════════════════════════════════
  //  Unit Conversions — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertUnitConversion(Map<String, dynamic> conversionMap) => refData.insertUnitConversion(conversionMap);
  Future<List<Map<String, dynamic>>> getUnitConversions(int productId) => refData.getUnitConversions(productId);
  Future<int> updateUnitConversion(int id, Map<String, dynamic> conversionMap) => refData.updateUnitConversion(id, conversionMap);
  Future<int> deleteUnitConversion(int id) => refData.deleteUnitConversion(id);
  Future<Map<String, dynamic>?> findUnitConversionByBarcode(String barcode) => refData.findUnitConversionByBarcode(barcode);
  Future<List<Map<String, dynamic>>> getAvailableUnitsForProduct(int productId) => refData.getAvailableUnitsForProduct(productId);

  // ══════════════════════════════════════════════════════════════
  //  Weighted Average Cost
  // ══════════════════════════════════════════════════════════════

  /// Update weighted average cost when purchasing at a new price.
  /// Formula: new_avg_cost = (existing_stock * old_avg_cost + new_qty * new_cost) / (existing_stock + new_qty)
  Future<void> updateWeightedAverageCost(int productId, double purchasedQty, double purchasedUnitCost) => products.updateWeightedAverageCost(productId, purchasedQty, purchasedUnitCost);

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
  }) => products.logStockMovement(
    productId: productId,
    movementType: movementType,
    quantity: quantity,
    referenceType: referenceType,
    referenceId: referenceId,
    notes: notes,
    unitCost: unitCost,
  );

  /// Get stock movement history for a product
  Future<List<Map<String, dynamic>>> getStockMovements(int productId, {int limit = 50}) => products.getStockMovements(productId, limit: limit);

  /// Get stock movements by type (e.g., all sales today)
  Future<List<Map<String, dynamic>>> getStockMovementsByType(String movementType, {DateTime? since}) => products.getStockMovementsByType(movementType, since: since);

  // ══════════════════════════════════════════════════════════════
  //  Invoice CRUD methods — delegated to InvoiceRepository
  // ══════════════════════════════════════════════════════════════

  Future<void> insertInvoiceWithItems(
    Map<String, dynamic> invoiceMap,
    List<Map<String, dynamic>> items,
  ) => invoices.insertInvoiceWithItems(invoiceMap, items);

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
  }) => invoices.saveInvoiceWithJournalEntries(
    invoiceMap, items,
    invoiceType: invoiceType,
    paymentMechanism: paymentMechanism,
    isReturn: isReturn,
    cashBoxId: cashBoxId,
    transportCharges: transportCharges,
    deferPosting: deferPosting,
    paidAmount: paidAmount,
  );

  Future<List<Map<String, dynamic>>> getAllInvoices({String orderBy = 'created_at DESC', int? limit, int offset = 0}) => invoices.getAllInvoices(orderBy: orderBy, limit: limit, offset: offset);
  Future<List<Invoice>> getAllInvoiceObjects({String orderBy = 'created_at DESC', int? limit, int offset = 0}) => invoices.getAllInvoiceObjects(orderBy: orderBy, limit: limit, offset: offset);
  Future<List<Map<String, dynamic>>> getInvoicesByType(String type) => invoices.getInvoicesByType(type);
  Future<List<Invoice>> getInvoiceObjectsByType(String type) => invoices.getInvoiceObjectsByType(type);
  Future<List<Map<String, dynamic>>> getInvoiceItems(String invoiceId) => invoices.getInvoiceItems(invoiceId);
  Future<Map<String, dynamic>?> getInvoiceById(String invoiceId) => invoices.getInvoiceById(invoiceId);
  Future<Invoice?> getInvoiceObjectById(String invoiceId) => invoices.getInvoiceObjectById(invoiceId);
  Future<List<Map<String, dynamic>>> getLinkedReturns(String invoiceId) => invoices.getLinkedReturns(invoiceId);
  Future<int> deleteInvoice(String id) => invoices.deleteInvoice(id);
  /// M-14: Delete invoice with CASCADE (deletes related items, transactions, stock movements).
  Future<int> deleteInvoiceWithCascade(String invoiceId) => invoices.deleteInvoiceWithCascade(invoiceId);
  /// C-07: Cancel invoice with full reversal of journal entries and stock movements.
  Future<void> cancelInvoice(String invoiceId) => invoices.cancelInvoice(invoiceId);
  Future<void> recordInvoicePayment({
    required String invoiceId,
    required double amount,
    required int cashBoxId,
    String paymentMethod = 'cash',
    String? notes,
  }) => invoices.recordInvoicePayment(
    invoiceId: invoiceId,
    amount: amount,
    cashBoxId: cashBoxId,
    paymentMethod: paymentMethod,
    notes: notes,
  );
  Future<Map<String, String>> checkReturnLimits(String originalInvoiceId, List<Map<String, dynamic>> returnItems) => invoices.checkReturnLimits(originalInvoiceId, returnItems);

  // ══════════════════════════════════════════════════════════════
  //  Expense CRUD methods — delegated to ExpenseRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertExpense(Map<String, dynamic> expenseMap) => expenses.insertExpense(expenseMap);
  Future<List<Map<String, dynamic>>> getAllExpenses({String orderBy = 'expense_date DESC'}) => expenses.getAllExpenses(orderBy: orderBy);
  Future<List<Map<String, dynamic>>> getExpensesByCategory(String category) => expenses.getExpensesByCategory(category);
  Future<List<Map<String, dynamic>>> getExpensesByDateRange(String startDate, String endDate) => expenses.getExpensesByDateRange(startDate, endDate);
  Future<Map<String, dynamic>?> getExpenseById(int id) => expenses.getExpenseById(id);
  Future<int> updateExpense(int id, Map<String, dynamic> expenseMap) => expenses.updateExpense(id, expenseMap);
  Future<int> deleteExpense(int id) => expenses.deleteExpense(id);
  Future<double> getTotalExpensesThisMonth() => expenses.getTotalExpensesThisMonth();
  Future<double> getTotalExpensesByCategory(String category) => expenses.getTotalExpensesByCategory(category);
  Future<double> getTotalExpensesForDate(DateTime date) => expenses.getTotalExpensesForDate(date);
  Future<void> saveExpenseWithJournalEntry(Map<String, dynamic> expenseMap) => expenses.saveExpenseWithJournalEntry(expenseMap);

  // ══════════════════════════════════════════════════════════════
  //  Expense Account methods
  // ══════════════════════════════════════════════════════════════

  /// Get all expense accounts (accounts with type='EXPENSE')
  Future<List<Map<String, dynamic>>> getExpenseAccounts() => accounts.getExpenseAccounts();

  /// Get expense accounts filtered by currency
  Future<List<Map<String, dynamic>>> getExpenseAccountsByCurrency(String currency) => accounts.getExpenseAccountsByCurrency(currency);

  /// Get all expenses for a specific expense account
  Future<List<Map<String, dynamic>>> getExpensesByAccountId(int accountId, {String orderBy = 'expense_date DESC'}) => expenses.getExpensesByAccountId(accountId, orderBy: orderBy);

  /// Delegates to [JournalService.getAccountTransactions].
  Future<List<Map<String, dynamic>>> getAccountTransactions(int accountId) =>
      journal.getAccountTransactions(accountId);

  /// Delegates to [JournalService.getAccountBalance].
  Future<double> getAccountBalance(int accountId) =>
      journal.getAccountBalance(accountId);

  /// Create an expense account with optional opening balance
  Future<int> createExpenseAccount({
    required String nameAr,
    required String currency,
    double? debtCeiling,
    double openingBalance = 0.0,
    String balanceType = 'credit', // 'credit' = له, 'debit' = عليه
    String? notes,
  }) => accounts.createExpenseAccount(
    nameAr: nameAr,
    currency: currency,
    debtCeiling: debtCeiling,
    openingBalance: openingBalance,
    balanceType: balanceType,
    notes: notes,
  );

  // ══════════════════════════════════════════════════════════════
  //  Category methods — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllCategories() => refData.getAllCategories();
  Future<int> insertCategory(Map<String, dynamic> categoryMap) => refData.insertCategory(categoryMap);
  Future<int> deleteCategory(int id) => refData.deleteCategory(id);
  Future<int> updateCategory(int id, Map<String, dynamic> categoryMap) => refData.updateCategory(id, categoryMap);

  // ══════════════════════════════════════════════════════════════
  //  Warehouse methods — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllWarehouses() => refData.getAllWarehouses();
  Future<int> insertWarehouse(Map<String, dynamic> warehouseMap) => refData.insertWarehouse(warehouseMap);
  Future<int> updateWarehouse(int id, Map<String, dynamic> warehouseMap) => refData.updateWarehouse(id, warehouseMap);
  Future<int> deleteWarehouse(int id) => refData.deleteWarehouse(id);
  Future<List<Map<String, dynamic>>> searchWarehouses(String query) => refData.searchWarehouses(query);

  Future<int> getProductCountByWarehouse(int warehouseId) => products.getProductCountByWarehouse(warehouseId);

  // ══════════════════════════════════════════════════════════════
  //  Account methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getAllAccounts() => accounts.getAllAccounts();
  Future<List<Account>> getAllAccountObjects() => accounts.getAllAccountObjects();

  Future<List<Map<String, dynamic>>> getAccountsByType(String accountType) => accounts.getAccountsByType(accountType);
  Future<List<Account>> getAccountObjectsByType(String accountType) => accounts.getAccountObjectsByType(accountType);

  Future<List<Map<String, dynamic>>> getAccountsByCurrency(String currencyCode) => accounts.getAccountsByCurrency(currencyCode);

  Future<int> insertAccount(Map<String, dynamic> accountMap) => accounts.insertAccount(accountMap);

  Future<int> updateAccount(int id, Map<String, dynamic> accountMap) => accounts.updateAccount(id, accountMap);

  Future<int> deleteAccount(int id) => accounts.deleteAccount(id);

  /// Get the next available account code for a given account type.
  /// Uses 4-digit numeric codes where the first digit is the type prefix.
  /// Steps by 10 to leave room for sub-accounts.
  Future<String> getNextAccountCode(String accountType) => accounts.getNextAccountCode(accountType);

  Future<List<Map<String, dynamic>>> getAccountsWithoutMovements() => accounts.getAccountsWithoutMovements();

  /// Delegates to [JournalService.reconcileAccountBalance].
  Future<void> reconcileAccountBalance(int accountId) =>
      journal.reconcileAccountBalance(accountId);

  // ══════════════════════════════════════════════════════════════
  //  Employee CRUD methods — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertEmployee(Map<String, dynamic> employeeMap) => refData.insertEmployee(employeeMap);
  Future<List<Map<String, dynamic>>> getAllEmployees() => refData.getAllEmployees();
  Future<Map<String, dynamic>?> getEmployeeById(int id) => refData.getEmployeeById(id);
  Future<int> updateEmployee(int id, Map<String, dynamic> employeeMap) => refData.updateEmployee(id, employeeMap);
  Future<int> deleteEmployee(int id) => refData.deleteEmployee(id);
  Future<List<Map<String, dynamic>>> getEmployees() => refData.getEmployees();

  // ══════════════════════════════════════════════════════════════
  //  Settings methods — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<String?> getSetting(String key) => refData.getSetting(key);
  Future<void> setSetting(String key, String value) => refData.setSetting(key, value);
  Future<void> deleteSetting(String key) => refData.deleteSetting(key);

  // ══════════════════════════════════════════════════════════════
  //  Dashboard query methods
  // ══════════════════════════════════════════════════════════════

  Future<double> getTotalSalesForDate(DateTime date) => invoices.getTotalSalesForDate(date);
  Future<double> getTotalPurchasesThisMonth() => invoices.getTotalPurchasesThisMonth();
  Future<double> getTotalSalesThisMonth() => invoices.getTotalSalesThisMonth();
  Future<double> getCOGSThisMonth() => invoices.getCOGSThisMonth();
  Future<int> getInvoiceCountForDate(DateTime date) => invoices.getInvoiceCountForDate(date);

  Future<double> getCashBalance() => invoices.getCashBalance();

  Future<List<Map<String, dynamic>>> getRecentInvoices({int limit = 10}) => invoices.getRecentInvoices(limit: limit);
  Future<List<Map<String, dynamic>>> getDailySalesTotals({int days = 7}) => invoices.getDailySalesTotals(days: days);

  // ══════════════════════════════════════════════════════════════
  //  Additional utility methods
  // ══════════════════════════════════════════════════════════════

  /// Delegates to [JournalService.getTransactionsByAccount].
  Future<List<Map<String, dynamic>>> getTransactionsByAccount(int accountId) =>
      journal.getTransactionsByAccount(accountId);

  // ══════════════════════════════════════════════════════════════
  //  Notification CRUD methods — delegated to ReferenceDataRepository
  // ══════════════════════════════════════════════════════════════

  Future<int> insertNotification(Map<String, dynamic> notificationMap) => refData.insertNotification(notificationMap);
  Future<List<Map<String, dynamic>>> getAllNotifications({String orderBy = 'created_at DESC'}) => refData.getAllNotifications(orderBy: orderBy);
  Future<List<Map<String, dynamic>>> getNotificationsByType(String type, {String orderBy = 'created_at DESC'}) => refData.getNotificationsByType(type, orderBy: orderBy);
  Future<int> markNotificationAsRead(int id) => refData.markNotificationAsRead(id);
  Future<int> deleteNotification(int id) => refData.deleteNotification(id);

  // ══════════════════════════════════════════════════════════════
  //  Quotation CRUD methods — delegated to OrderRepository
  // ══════════════════════════════════════════════════════════════

  Future<void> insertQuotationWithItems(Map<String, dynamic> quotationMap, List<Map<String, dynamic>> items) => orders.insertQuotationWithItems(quotationMap, items);
  Future<List<Map<String, dynamic>>> getAllQuotations({String orderBy = 'created_at DESC'}) => orders.getAllQuotations(orderBy: orderBy);
  Future<List<Map<String, dynamic>>> getQuotationsByStatus(String status) => orders.getQuotationsByStatus(status);
  Future<Map<String, dynamic>?> getQuotationById(String id) => orders.getQuotationById(id);
  Future<List<Map<String, dynamic>>> getQuotationItems(String quotationId) => orders.getQuotationItems(quotationId);
  Future<int> updateQuotation(String id, Map<String, dynamic> quotationMap) => orders.updateQuotation(id, quotationMap);
  Future<int> deleteQuotation(String id) => orders.deleteQuotation(id);
  Future<String> getNextQuotationNumber() => orders.getNextQuotationNumber();

  // ══════════════════════════════════════════════════════════════
  //  Purchase Order CRUD methods — delegated to OrderRepository
  // ══════════════════════════════════════════════════════════════

  Future<void> insertPurchaseOrderWithItems(Map<String, dynamic> poMap, List<Map<String, dynamic>> items) => orders.insertPurchaseOrderWithItems(poMap, items);
  Future<List<Map<String, dynamic>>> getAllPurchaseOrders({String orderBy = 'created_at DESC'}) => orders.getAllPurchaseOrders(orderBy: orderBy);
  Future<List<Map<String, dynamic>>> getPurchaseOrdersByStatus(String status) => orders.getPurchaseOrdersByStatus(status);
  Future<Map<String, dynamic>?> getPurchaseOrderById(String id) => orders.getPurchaseOrderById(id);
  Future<List<Map<String, dynamic>>> getPurchaseOrderItems(String poId) => orders.getPurchaseOrderItems(poId);
  Future<int> updatePurchaseOrder(String id, Map<String, dynamic> poMap) => orders.updatePurchaseOrder(id, poMap);
  Future<int> deletePurchaseOrder(String id) => orders.deletePurchaseOrder(id);
  Future<String> getNextPurchaseOrderNumber() => orders.getNextPurchaseOrderNumber();

  // ══════════════════════════════════════════════════════════════
  //  Sales Order CRUD methods — delegated to OrderRepository
  // ══════════════════════════════════════════════════════════════

  Future<void> insertSalesOrderWithItems(Map<String, dynamic> soMap, List<Map<String, dynamic>> items) => orders.insertSalesOrderWithItems(soMap, items);
  Future<List<Map<String, dynamic>>> getAllSalesOrders({String orderBy = 'created_at DESC'}) => orders.getAllSalesOrders(orderBy: orderBy);
  Future<List<Map<String, dynamic>>> getSalesOrdersByStatus(String status) => orders.getSalesOrdersByStatus(status);
  Future<Map<String, dynamic>?> getSalesOrderById(String id) => orders.getSalesOrderById(id);
  Future<List<Map<String, dynamic>>> getSalesOrderItems(String soId) => orders.getSalesOrderItems(soId);
  Future<int> updateSalesOrder(String id, Map<String, dynamic> soMap) => orders.updateSalesOrder(id, soMap);
  Future<int> deleteSalesOrder(String id) => orders.deleteSalesOrder(id);
  Future<String> getNextSalesOrderNumber() => orders.getNextSalesOrderNumber();

  // ══════════════════════════════════════════════════════════════
  //  Shift (وردية) CRUD methods — delegated to ShiftService
  // ══════════════════════════════════════════════════════════════

  Future<int> openShift(Map<String, dynamic> shiftMap) => shifts.openShift(shiftMap);
  Future<Map<String, dynamic>?> getActiveShift(int cashBoxId) => shifts.getActiveShift(cashBoxId);
  Future<Map<String, dynamic>?> getActiveShiftForCashier(int? cashierId) => shifts.getActiveShiftForCashier(cashierId);
  Future<int> closeShift(int shiftId, Map<String, dynamic> closeData) => shifts.closeShift(shiftId, closeData);
  Future<List<Map<String, dynamic>>> getAllShifts({String orderBy = 'opened_at DESC'}) => shifts.getAllShifts(orderBy: orderBy);
  Future<String> getNextShiftNumber() => shifts.getNextShiftNumber();
  Future<void> updateShiftTotals(int shiftId, double saleAmount, double returnAmount, double discountAmount) => shifts.updateShiftTotals(shiftId, saleAmount, returnAmount, discountAmount);

  // ══════════════════════════════════════════════════════════════
  //  v12: Currency Exchange (صرافة العملات) — delegated to CashBoxService
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCurrencyExchange(Map<String, dynamic> exchangeMap) => cashBoxes.insertCurrencyExchange(exchangeMap);
  Future<List<Map<String, dynamic>>> getAllCurrencyExchanges({String orderBy = 'created_at DESC'}) => cashBoxes.getAllCurrencyExchanges(orderBy: orderBy);
  Future<String> getNextExchangeNumber() => cashBoxes.getNextExchangeNumber();

  // ══════════════════════════════════════════════════════════════
  //  v12: Cash Transfer (تحويل بين الصناديق) — delegated to CashBoxService
  // ══════════════════════════════════════════════════════════════

  Future<int> insertCashTransfer(Map<String, dynamic> transferMap) => cashBoxes.insertCashTransfer(transferMap);
  Future<List<Map<String, dynamic>>> getAllCashTransfers({String orderBy = 'created_at DESC'}) => cashBoxes.getAllCashTransfers(orderBy: orderBy);
  Future<String> getNextTransferNumber() => cashBoxes.getNextTransferNumber();

  // ══════════════════════════════════════════════════════════════
  //  v12: Shift Invoice & Posting methods — delegated to ShiftService
  // ══════════════════════════════════════════════════════════════

  /// جلب جميع فواتير الوردية المحددة
  /// Get all invoices for a specific shift.
  Future<List<Map<String, dynamic>>> getShiftInvoices(int shiftId) => shifts.getShiftInvoices(shiftId);

  /// ترحيل جميع الفواتير المعلقة في وردية محددة
  /// Post all pending invoices in a shift by creating journal entries.
  Future<int> postShiftInvoices(int shiftId) => shifts.postShiftInvoices(shiftId);

  // ══════════════════════════════════════════════════════════════
  //  v12: Additional lookup methods
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getCashBoxesByCurrency(String currency) => cashBoxes.getCashBoxesByCurrency(currency);

  /// Delegates to [JournalService.getAccountByCodeAndCurrency].
  Future<Map<String, dynamic>?> getAccountByCodeAndCurrency(String code, String currency) =>
      journal.getAccountByCodeAndCurrency(code, currency);

  /// Count POS invoices for a given date prefix (e.g. '2026-03-04')
  /// Used to avoid invoice-ID collisions after app restart.
  // ══════════════════════════════════════════════════════════════
  //  Voucher (السندات) — delegated to CashBoxService
  // ══════════════════════════════════════════════════════════════

  Future<int> insertVoucher(Map<String, dynamic> voucherMap, List<Map<String, dynamic>> items) => cashBoxes.insertVoucher(voucherMap, items);
  Future<List<Map<String, dynamic>>> getAllVouchers({String? type, String orderBy = 'created_at DESC'}) => cashBoxes.getAllVouchers(type: type, orderBy: orderBy);
  Future<List<Map<String, dynamic>>> getVoucherItems(int voucherId) => cashBoxes.getVoucherItems(voucherId);
  Future<int> deleteVoucher(int voucherId) => cashBoxes.deleteVoucher(voucherId);
  Future<Map<String, dynamic>?> getVoucherByNumber(String number) => cashBoxes.getVoucherByNumber(number);
  Future<String> getNextVoucherNumber(String type) => cashBoxes.getNextVoucherNumber(type);

  Future<int> getTodayPosInvoiceCount(String datePrefix) => invoices.getTodayPosInvoiceCount(datePrefix);

  // ══════════════════════════════════════════════════════════════
  //  العمليات اليومية والتقارير الإضافية — delegated to ReportService
  //  Daily Operations & Additional Reports
  // ══════════════════════════════════════════════════════════════

  /// جلب العمليات اليومية المجمعة لتاريخ محدد
  Future<List<Map<String, dynamic>>> getDailyOperations(DateTime date) => reports.getDailyOperations(date);
  /// جلب ملخص العمليات اليومية لتاريخ محدد
  Future<Map<String, double>> getDailySummary(DateTime date) => reports.getDailySummary(date);
  /// جلب تقرير أرباح الفواتير
  Future<List<Map<String, dynamic>>> getInvoiceProfitReport({DateTime? startDate, DateTime? endDate}) => reports.getInvoiceProfitReport(startDate: startDate, endDate: endDate);
  /// جلب تقرير حركة المخزون
  Future<List<Map<String, dynamic>>> getInventoryMovementReport({DateTime? startDate, DateTime? endDate}) => reports.getInventoryMovementReport(startDate: startDate, endDate: endDate);
  /// جلب تقرير تكلفة المخزون
  Future<List<Map<String, dynamic>>> getInventoryCostReport() => reports.getInventoryCostReport();

  // ══════════════════════════════════════════════════════════════
  //  Stock Transfer methods (تحويل مخزني) — delegated to StockService
  // ══════════════════════════════════════════════════════════════

  /// إدراج تحويل مخزني وتحديث المخزون + تسجيل حركات المخزون
  Future<int> insertStockTransfer(Map<String, dynamic> transferMap) => stock.insertStockTransfer(transferMap);
  /// جلب جميع التحويلات المخزنية مع أسماء المستودعات والمنتجات
  Future<List<Map<String, dynamic>>> getAllStockTransfers() => stock.getAllStockTransfers();

  /// جلب كمية المخزون لمنتج في مخزن محدد
  /// Get the stock quantity for a specific product in a specific warehouse.
  /// Returns null if the product doesn't exist in that warehouse.
  Future<double?> getProductStockInWarehouse(int productId, int warehouseId) => products.getProductStockInWarehouse(productId, warehouseId);

  // ══════════════════════════════════════════════════════════════
  //  Stocktaking methods (جرد المخازن) — delegated to StockService
  // ══════════════════════════════════════════════════════════════

  /// إنشاء جلسة جرد مع عناصرها
  Future<int> createStocktakingSession(Map<String, dynamic> sessionMap, List<Map<String, dynamic>> items) => stock.createStocktakingSession(sessionMap, items);
  /// إكمال جلسة الجرد وتحديث المخزون الفعلي مع تسجيل الفرق والتدقيق + قيود يومية + حركات مخزون
  Future<void> completeStocktakingSession(int sessionId) => stock.completeStocktakingSession(sessionId);
  /// جلب جميع جلسات الجرد
  Future<List<Map<String, dynamic>>> getStocktakingSessions() => stock.getStocktakingSessions();
  /// جلب عناصر جلسة الجرد
  Future<List<Map<String, dynamic>>> getStocktakingItems(int sessionId) => stock.getStocktakingItems(sessionId);

  /// جلب جميع الحركات المحاسبية للتصدير مع اسم الحساب
  Future<List<Map<String, dynamic>>> getAllTransactionsForExport() => reports.getAllTransactionsForExport();

  // ══════════════════════════════════════════════════════════════
  //  Advanced Statistics / Charts query methods — delegated to ReportService
  // ══════════════════════════════════════════════════════════════

  /// Monthly sales vs purchases for a given [year].
  Future<List<Map<String, dynamic>>> getMonthlySalesVsPurchases(int year, {String? currency}) => reports.getMonthlySalesVsPurchases(year, currency: currency);
  /// Revenue vs Expense breakdown for a given [year].
  Future<List<Map<String, dynamic>>> getRevenueExpenseBreakdown(int year, {String? currency}) => reports.getRevenueExpenseBreakdown(year, currency: currency);
  /// Daily sales trend for the last [days] days.
  Future<List<Map<String, dynamic>>> getDailySalesTrend(int days, {String? currency}) => reports.getDailySalesTrend(days, currency: currency);
  /// Top products by sales amount.
  Future<List<Map<String, dynamic>>> getTopProducts(int limit, {String? currency}) => reports.getTopProducts(limit, currency: currency);
  /// Monthly cash flow (inflow vs outflow) for a given [year].
  Future<List<Map<String, dynamic>>> getMonthlyCashFlow(int year, {String? currency}) => reports.getMonthlyCashFlow(year, currency: currency);

  // ══════════════════════════════════════════════════════════════
  //  Inventory Voucher Methods (سندات الجرد) - v22 — delegated to StockService
  // ══════════════════════════════════════════════════════════════

  Future<String> getNextInventoryVoucherNumber() => stock.getNextInventoryVoucherNumber();
  Future<int> insertInventoryVoucher(Map<String, dynamic> voucherMap, List<Map<String, dynamic>> items) => stock.insertInventoryVoucher(voucherMap, items);
  Future<List<Map<String, dynamic>>> getInventoryVouchers({String? searchQuery}) => stock.getInventoryVouchers(searchQuery: searchQuery);
  Future<Map<String, dynamic>?> getInventoryVoucherDetails(int voucherId) => stock.getInventoryVoucherDetails(voucherId);
  Future<List<Map<String, dynamic>>> getAllInventoryVouchers() => stock.getAllInventoryVouchers();
  Future<void> deleteInventoryVoucher(int id) => stock.deleteInventoryVoucher(id);
  Future<void> confirmInventoryVoucher(int id) => stock.confirmInventoryVoucher(id);

  // ══════════════════════════════════════════════════════════════
  //  Annual Posting Methods (الترحيل السنوي) - v22
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getFiscalYears() => accounts.getFiscalYears();

  Future<bool> isFiscalYearClosed(int year) => accounts.isFiscalYearClosed(year);

  /// Check if a date falls in a closed fiscal year
  Future<bool> isDateInClosedPeriod(DateTime date) => accounts.isDateInClosedPeriod(date);

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
  }) => audit.logAuditEvent(
    action: action,
    tableName: tableName,
    recordId: recordId,
    recordType: recordType,
    oldValues: oldValues,
    newValues: newValues,
    userName: userName,
    shiftId: shiftId,
  );

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
  Future<int> getNextInvoiceSequence(String datePrefix, String invoiceType) => invoices.getNextInvoiceSequence(datePrefix, invoiceType);

  /// حساب مكاسب/خسائر الصرف الأجنبي
  /// تُحسب عند إقفال الفترة أو عند تسوية حساب بعملة مختلفة
  /// formula: gain/loss = (base_amount * current_rate) - (base_amount * original_rate)
  /// Delegates to [JournalService.calculateExchangeGainLoss].
  Future<double> calculateExchangeGainLoss({
    required double baseAmount,
    required double originalRate,
    required double currentRate,
  }) =>
      journal.calculateExchangeGainLoss(
        baseAmount: baseAmount,
        originalRate: originalRate,
        currentRate: currentRate,
      );

  /// Delegates to [JournalService.recordExchangeGainLoss].
  Future<void> recordExchangeGainLoss({
    required int accountId,
    required double gainLossAmount,
    required String currency,
    required String referenceId,
  }) =>
      journal.recordExchangeGainLoss(
        accountId: accountId,
        gainLossAmount: gainLossAmount,
        currency: currency,
        referenceId: referenceId,
      );

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
      'balance': 0,
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
    final totalDebit = entries.fold(0.0, (sum, e) => sum + MoneyHelper.readMoney(e['debit']));
    final totalCredit = entries.fold(0.0, (sum, e) => sum + MoneyHelper.readMoney(e['credit']));
    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception('القيد غير متوازن: المدين = $totalDebit، الدائن = $totalCredit. يجب أن يتساوى المدين والدائن.');
    }
  }

  Future<Map<String, double>> getYearProfitLoss(int year) => accounts.getYearProfitLoss(year);

  Future<void> performAnnualPosting(int year) => accounts.performAnnualPosting(year);

  // ══════════════════════════════════════════════════════════════
  //  v33: Held Orders (POS) CRUD methods — delegated to ShiftService
  // ══════════════════════════════════════════════════════════════

  Future<int> insertHeldOrder(Map<String, dynamic> order) => shifts.insertHeldOrder(order);
  Future<List<Map<String, dynamic>>> getHeldOrders({int? shiftId}) => shifts.getHeldOrders(shiftId: shiftId);
  Future<int> deleteHeldOrder(int id) => shifts.deleteHeldOrder(id);
  Future<void> clearHeldOrders({int? shiftId}) => shifts.clearHeldOrders(shiftId: shiftId);
}
