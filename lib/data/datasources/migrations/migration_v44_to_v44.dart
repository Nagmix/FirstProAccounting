import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v44: Create license_state table for the license system.
class MigrationV44 {
  static Future<void> migrate(Database db) async {
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

    // Insert default free state row
    await db.execute('''
      INSERT OR IGNORE INTO license_state (id, license_type, status, record_count)
      VALUES (1, 'free', 'free', 0)
    ''');
  }
}
