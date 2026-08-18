import 'package:sqflite_sqlcipher/sqflite.dart';

/// Additive production and recipe schema for bakeries and food preparation.
class MigrationV58 {
  static Future<void> migrate(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        output_product_id INTEGER NOT NULL UNIQUE,
        name TEXT NOT NULL,
        output_quantity REAL NOT NULL CHECK (output_quantity > 0),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (output_product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recipe_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL,
        component_product_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE,
        FOREIGN KEY (component_product_id) REFERENCES products(id),
        UNIQUE (recipe_id, component_product_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS production_orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL UNIQUE,
        recipe_id INTEGER NOT NULL,
        output_product_id INTEGER NOT NULL,
        planned_quantity REAL NOT NULL CHECK (planned_quantity > 0),
        actual_quantity REAL NOT NULL DEFAULT 0 CHECK (actual_quantity >= 0),
        status TEXT NOT NULL DEFAULT 'draft',
        currency_code TEXT NOT NULL DEFAULT 'YER',
        exchange_rate REAL NOT NULL DEFAULT 1.0 CHECK (exchange_rate > 0),
        total_cost INTEGER NOT NULL DEFAULT 0,
        waste_cost INTEGER NOT NULL DEFAULT 0,
        is_posted INTEGER NOT NULL DEFAULT 0 CHECK (is_posted IN (0, 1)),
        posted_journal_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (recipe_id) REFERENCES recipes(id),
        FOREIGN KEY (output_product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS production_consumptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        production_order_id TEXT NOT NULL,
        component_product_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_cost INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
        total_cost INTEGER NOT NULL DEFAULT 0 CHECK (total_cost >= 0),
        created_at TEXT NOT NULL,
        FOREIGN KEY (production_order_id)
          REFERENCES production_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (component_product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS production_outputs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        production_order_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        total_cost INTEGER NOT NULL DEFAULT 0 CHECK (total_cost >= 0),
        created_at TEXT NOT NULL,
        FOREIGN KEY (production_order_id)
          REFERENCES production_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS production_status_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        production_order_id TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT NOT NULL,
        note TEXT,
        changed_by INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (production_order_id)
          REFERENCES production_orders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipes_output_product '
      'ON recipes(output_product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipe_lines_recipe '
      'ON recipe_lines(recipe_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipe_lines_component '
      'ON recipe_lines(component_product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_orders_status '
      'ON production_orders(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_orders_recipe '
      'ON production_orders(recipe_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_consumptions_order '
      'ON production_consumptions(production_order_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_outputs_order '
      'ON production_outputs(production_order_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_production_status_history_order '
      'ON production_status_history(production_order_id, created_at)',
    );
  }
}
