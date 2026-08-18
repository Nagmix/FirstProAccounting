import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v56 — explicit product kinds for goods and services.
///
/// Existing products remain stock items by default. The explicit kind is
/// intentionally separate from track_stock so legacy behavior is preserved
/// while service items can be configured without creating inventory movements.
class MigrationV56 {
  static Future<void> migrate(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(products)');
    final hasProductKind = columns.any((row) => row['name'] == 'product_kind');
    if (!hasProductKind) {
      await db.execute(
        "ALTER TABLE products ADD COLUMN product_kind TEXT NOT NULL DEFAULT 'stock'",
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_kind ON products (product_kind)',
    );
  }
}
