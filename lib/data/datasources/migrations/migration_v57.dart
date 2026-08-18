import 'package:sqflite_sqlcipher/sqflite.dart';

/// Service and maintenance workflow tables.
///
/// This migration is intentionally additive. Historical migrations must remain
/// unchanged because existing databases upgrade through them in order.
class MigrationV57 {
  static Future<void> migrate(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER,
        status TEXT NOT NULL DEFAULT 'draft',
        priority TEXT NOT NULL DEFAULT 'normal',
        received_at TEXT NOT NULL,
        promised_at TEXT,
        completed_at TEXT,
        delivered_at TEXT,
        currency_code TEXT NOT NULL DEFAULT 'YER',
        exchange_rate REAL NOT NULL DEFAULT 1.0 CHECK (exchange_rate > 0),
        subtotal INTEGER NOT NULL DEFAULT 0,
        discount_amount INTEGER NOT NULL DEFAULT 0,
        tax_amount INTEGER NOT NULL DEFAULT 0,
        transport_charges INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL DEFAULT 0,
        paid_amount INTEGER NOT NULL DEFAULT 0,
        remaining INTEGER NOT NULL DEFAULT 0,
        is_posted INTEGER NOT NULL DEFAULT 0 CHECK (is_posted IN (0, 1)),
        posted_journal_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_order_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id TEXT NOT NULL,
        device_type TEXT NOT NULL,
        brand TEXT,
        model TEXT,
        serial_number TEXT,
        imei TEXT,
        condition_on_receipt TEXT,
        accessories TEXT,
        customer_approval_note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_order_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id TEXT NOT NULL,
        line_type TEXT NOT NULL CHECK (line_type IN ('service', 'part')),
        product_id INTEGER,
        description TEXT NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_price INTEGER NOT NULL DEFAULT 0,
        unit_cost INTEGER NOT NULL DEFAULT 0,
        tax_rate REAL NOT NULL DEFAULT 0.0 CHECK (tax_rate >= 0),
        tax_amount INTEGER NOT NULL DEFAULT 0,
        line_total INTEGER NOT NULL DEFAULT 0,
        currency_code TEXT NOT NULL DEFAULT 'YER',
        is_posted INTEGER NOT NULL DEFAULT 0 CHECK (is_posted IN (0, 1)),
        created_at TEXT NOT NULL,
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_status_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT NOT NULL,
        note TEXT,
        changed_by INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id TEXT NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        amount INTEGER NOT NULL CHECK (amount > 0),
        currency_code TEXT NOT NULL DEFAULT 'YER',
        exchange_rate REAL NOT NULL DEFAULT 1.0 CHECK (exchange_rate > 0),
        amount_base INTEGER NOT NULL DEFAULT 0,
        cash_box_id INTEGER,
        reference_number TEXT,
        is_posted INTEGER NOT NULL DEFAULT 0 CHECK (is_posted IN (0, 1)),
        journal_id INTEGER,
        payment_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id) ON DELETE RESTRICT,
        FOREIGN KEY (cash_box_id) REFERENCES cash_boxes(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS service_warranties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_order_id TEXT NOT NULL,
        service_order_line_id INTEGER,
        warranty_type TEXT NOT NULL DEFAULT 'repair',
        starts_at TEXT NOT NULL,
        ends_at TEXT NOT NULL,
        terms TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (ends_at >= starts_at),
        FOREIGN KEY (service_order_id)
          REFERENCES service_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (service_order_line_id)
          REFERENCES service_order_lines(id) ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_orders_status '
      'ON service_orders(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_orders_customer '
      'ON service_orders(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_order_devices_order '
      'ON service_order_devices(service_order_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_order_devices_identity '
      'ON service_order_devices(serial_number, imei)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_order_lines_order '
      'ON service_order_lines(service_order_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_order_lines_product '
      'ON service_order_lines(product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_status_history_order '
      'ON service_status_history(service_order_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_payments_order '
      'ON service_payments(service_order_id, payment_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_warranties_order '
      'ON service_warranties(service_order_id, status)',
    );
  }
}
