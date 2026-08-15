import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v55 — idempotency ledger for recurring invoice generation.
class MigrationV55 {
  static Future<void> migrate(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_invoice_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recurring_invoice_id INTEGER NOT NULL,
        scheduled_for TEXT NOT NULL,
        invoice_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(recurring_invoice_id, scheduled_for),
        UNIQUE(invoice_id),
        FOREIGN KEY (recurring_invoice_id)
          REFERENCES recurring_invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recurring_runs_invoice '
      'ON recurring_invoice_runs(recurring_invoice_id, scheduled_for)',
    );
  }
}
