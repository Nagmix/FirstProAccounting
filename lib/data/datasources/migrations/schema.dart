import 'package:sqflite_sqlcipher/sqflite.dart';
import 'seeds.dart';

class DatabaseSchema {
  /// Creates all tables for a fresh database installation.
  static Future<void> onCreate(Database db, int version) async {
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
        currency_code TEXT NOT NULL DEFAULT 'YER',
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        amount_base INTEGER NOT NULL DEFAULT 0,
        reference_type TEXT,
        reference_id TEXT,
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

    // Expense Sub-Accounts (الحسابات الفرعية للمصروفات) - v45
    // Created before expenses table so the FK reference is valid
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_sub_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        debt_ceiling INTEGER NOT NULL DEFAULT 0,
        phone TEXT,
        contact_method TEXT DEFAULT 'whatsapp',
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expense_sub_accounts_name ON expense_sub_accounts (name)');

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
        expense_sub_account_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
        FOREIGN KEY (account_id) REFERENCES accounts (id),
        FOREIGN KEY (expense_account_id) REFERENCES accounts (id),
        FOREIGN KEY (expense_sub_account_id) REFERENCES expense_sub_accounts (id)
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
    await db.execute('CREATE INDEX idx_transactions_currency ON transactions (currency_code)');
    await db.execute('CREATE INDEX idx_transactions_reference ON transactions (reference_type, reference_id)');
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_sub_account ON expenses (expense_sub_account_id)');
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
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        cash_box_id INTEGER,
        customer_id INTEGER,
        supplier_id INTEGER,
        employee_id INTEGER,
        is_posted INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (cash_box_id) REFERENCES cash_boxes (id),
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
        FOREIGN KEY (employee_id) REFERENCES employees (id)
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
    await db.execute('CREATE INDEX idx_vouchers_employee_id ON vouchers (employee_id)');
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
    await DatabaseSeeds.seedCurrencies(db);
    await DatabaseSeeds.seedDefaultAccounts(db);
    await DatabaseSeeds.seedDefaultUnits(db);

    // v44 — License state table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS license_state (
        id                  INTEGER PRIMARY KEY CHECK (id = 1),
        license_key         TEXT,
        license_type        TEXT,
        status              TEXT,
        expires_at          TEXT,
        device_fingerprint  TEXT,
        installation_id     TEXT,
        session_token       TEXT,
        last_validated_at   TEXT,
        last_sync_at        TEXT,
        record_count        INTEGER DEFAULT 0,
        is_offline_grace    INTEGER DEFAULT 0,
        offline_since       TEXT,
        server_url          TEXT
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO license_state (id, license_type, status, record_count)
      VALUES (1, 'free', 'free', 0)
    ''');
  }
}
