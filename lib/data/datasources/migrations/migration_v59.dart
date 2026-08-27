import 'package:sqflite_sqlcipher/sqflite.dart';

/// Additive general-platform foundation for typed profile, capabilities,
/// tax policy snapshots, document reversals, and migration diagnostics.
class MigrationV59 {
  static Future<void> migrate(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        business_name TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        logo_path TEXT,
        country_code TEXT NOT NULL DEFAULT 'YE',
        base_currency_code TEXT NOT NULL DEFAULT 'YER',
        locale TEXT NOT NULL DEFAULT 'ar',
        timezone TEXT NOT NULL DEFAULT 'Asia/Aden',
        tax_mode TEXT NOT NULL DEFAULT 'none',
        setup_status TEXT NOT NULL DEFAULT 'not_started',
        setup_version INTEGER NOT NULL DEFAULT 1,
        source TEXT NOT NULL DEFAULT 'migration',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_capabilities (
        capability_code TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        source TEXT NOT NULL,
        definition_version INTEGER NOT NULL DEFAULT 1,
        enabled_at TEXT,
        disabled_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_template_states (
        template_code TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        definition_version INTEGER NOT NULL DEFAULT 1,
        source TEXT NOT NULL,
        preferences_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS feature_flags (
        flag_key TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        default_enabled INTEGER NOT NULL CHECK (default_enabled IN (0, 1)),
        source TEXT NOT NULL,
        minimum_app_version TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tax_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        country_code TEXT NOT NULL,
        regime_code TEXT NOT NULL,
        name_ar TEXT NOT NULL,
        rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0),
        calculation_method TEXT NOT NULL,
        transport_taxable INTEGER NOT NULL CHECK (transport_taxable IN (0, 1)),
        valid_from TEXT NOT NULL,
        valid_to TEXT,
        requires_confirmation INTEGER NOT NULL CHECK (requires_confirmation IN (0, 1)),
        source_note TEXT,
        is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_tax_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        tax_profile_id INTEGER,
        country_code TEXT NOT NULL,
        regime_code TEXT NOT NULL,
        rate_bps INTEGER NOT NULL CHECK (rate_bps >= 0),
        calculation_method TEXT NOT NULL,
        transport_taxable INTEGER NOT NULL CHECK (transport_taxable IN (0, 1)),
        taxable_subtotal_minor INTEGER NOT NULL DEFAULT 0,
        taxable_transport_minor INTEGER NOT NULL DEFAULT 0,
        discount_minor INTEGER NOT NULL DEFAULT 0,
        tax_minor INTEGER NOT NULL DEFAULT 0,
        rounding_mode TEXT NOT NULL,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (document_type, document_id),
        FOREIGN KEY (tax_profile_id) REFERENCES tax_profiles(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_reversals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        original_journal_id INTEGER,
        reversal_journal_id INTEGER NOT NULL,
        reason TEXT NOT NULL,
        cancelled_at TEXT NOT NULL,
        source TEXT NOT NULL,
        UNIQUE (document_type, document_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_runs (
        migration_key TEXT PRIMARY KEY,
        from_version INTEGER NOT NULL,
        to_version INTEGER NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        error_code TEXT,
        error_message TEXT,
        checksum TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_tax_snapshots_document '
      'ON document_tax_snapshots(document_type, document_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_reversals_document '
      'ON document_reversals(document_type, document_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tax_profiles_country_dates '
      'ON tax_profiles(country_code, valid_from, valid_to)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_migration_runs_status '
      'ON migration_runs(status)',
    );

    await _backfillLegacySetup(db);
  }

  static Future<void> _backfillLegacySetup(Database db) async {
    final now = DateTime.now().toIso8601String();
    final businessName = await _readSetting(db, 'business_name');
    final configuredCurrency = await _readSetting(db, 'default_currency');
    final baseCurrency = await _resolveActiveCurrency(
      db,
      configuredCurrency,
    );

    await db.insert(
      'business_profile',
      {
        'id': 1,
        'business_name': businessName,
        'country_code': 'YE',
        'base_currency_code': baseCurrency,
        'locale': 'ar',
        'timezone': 'Asia/Aden',
        'tax_mode': 'none',
        'setup_status': 'not_started',
        'setup_version': 1,
        'source': 'migration',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    for (final code in const ['backup', 'settings', 'audit']) {
      await db.insert(
        'business_capabilities',
        {
          'capability_code': code,
          'enabled': 1,
          'source': 'migration',
          'definition_version': 1,
          'enabled_at': now,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<String?> _readSetting(Database db, String key) async {
    try {
      final rows = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.single['value'] as String?;
    } on DatabaseException {
      return null;
    }
  }

  static Future<String> _resolveActiveCurrency(
    Database db,
    String? configuredCode,
  ) async {
    if (configuredCode != null && configuredCode.trim().isNotEmpty) {
      final configured = await db.query(
        'currencies',
        columns: ['code'],
        where: 'code = ? AND is_active = 1',
        whereArgs: [configuredCode.trim().toUpperCase()],
        limit: 1,
      );
      if (configured.isNotEmpty) return configured.single['code'] as String;
    }

    final defaults = await db.query(
      'currencies',
      columns: ['code'],
      where: 'is_default = 1 AND is_active = 1',
      orderBy: 'id ASC',
      limit: 1,
    );
    if (defaults.isNotEmpty) return defaults.single['code'] as String;
    return 'YER';
  }
}
