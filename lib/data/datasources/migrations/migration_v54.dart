import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v54 — F-03: Recurring invoices (قوالب الفواتير المتكررة).
///
/// Creates two new tables:
///   - recurring_invoices: the template + schedule + next_run_date.
///   - recurring_invoice_items: the line items (productId, qty, unitPrice).
///
/// When the RecurringInvoiceService runs (on app launch + manually), it
/// checks for recurring_invoices whose next_run_date <= today, generates
/// a real invoice via InvoiceRepository.saveInvoiceWithJournalEntries,
/// and advances next_run_date by the frequency interval.
class MigrationV54 {
  static Future<void> migrate(Database db) async {
    // ── recurring_invoices ──
    // Stores the template + schedule. The template fields mirror the
    // invoices table so we can easily clone them when generating.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        -- Template name (user-facing label, e.g. "إيجار المحل الشهري")
        name TEXT NOT NULL,
        -- 'sale' or 'purchase' (the invoice type to generate)
        invoice_type TEXT NOT NULL DEFAULT 'sale',
        -- 'cash' or 'credit' (the payment mechanism)
        payment_mechanism TEXT NOT NULL DEFAULT 'credit',
        -- Frequency: 'daily', 'weekly', 'monthly', 'yearly'
        frequency TEXT NOT NULL DEFAULT 'monthly',
        -- Interval: every N frequency units (e.g. every 2 months = frequency='monthly', interval=2)
        interval_value INTEGER NOT NULL DEFAULT 1,
        -- Next run date (YYYY-MM-DD). The service generates invoices
        -- for any recurring_invoice whose next_run_date <= today.
        next_run_date TEXT NOT NULL,
        -- Optional end date (YYYY-MM-DD). If set, the recurring invoice
        -- is paused after this date. NULL = no end (indefinite).
        end_date TEXT,
        -- Customer or supplier ID (one of them, depending on invoice_type)
        customer_id INTEGER,
        supplier_id INTEGER,
        -- Cash box for cash payment mechanism
        cash_box_id INTEGER,
        -- Currency + exchange rate at template creation time
        currency TEXT NOT NULL DEFAULT 'YER',
        exchange_rate REAL NOT NULL DEFAULT 1.0,
        -- VAT rate at template creation time (stored as percentage, e.g. 15.0)
        vat_rate REAL NOT NULL DEFAULT 0.0,
        -- Discount (fixed amount in the invoice currency)
        discount_amount INTEGER NOT NULL DEFAULT 0,
        -- Transport charges (fixed amount)
        transport_charges INTEGER NOT NULL DEFAULT 0,
        -- Notes to copy into each generated invoice
        notes TEXT,
        -- 'active' or 'paused' — the service only processes 'active' ones
        status TEXT NOT NULL DEFAULT 'active',
        -- Counter of how many invoices have been generated from this template
        generated_count INTEGER NOT NULL DEFAULT 0,
        -- ID of the last generated invoice (for traceability)
        last_generated_invoice_id TEXT,
        -- Timestamps
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Index for the service's main query: WHERE status='active' AND next_run_date <= today
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_recurring_next_run ON recurring_invoices(status, next_run_date)",
    );

    // ── recurring_invoice_items ──
    // Stores the line items. Mirrors invoice_items but without the
    // invoice_id (it's linked via recurring_invoice_id instead).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recurring_invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1.0,
        unit_price INTEGER NOT NULL DEFAULT 0,
        total_price INTEGER NOT NULL DEFAULT 0,
        unit_name TEXT,
        conversion_factor REAL NOT NULL DEFAULT 1.0,
        base_quantity REAL NOT NULL DEFAULT 1.0,
        notes TEXT,
        FOREIGN KEY (recurring_invoice_id) REFERENCES recurring_invoices(id) ON DELETE CASCADE
      )
    ''');

    // Index for fetching items by recurring_invoice_id
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_recurring_items_ri ON recurring_invoice_items(recurring_invoice_id)",
    );
  }
}
