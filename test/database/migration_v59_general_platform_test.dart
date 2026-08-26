import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/migrations/migration_v59.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openV58Database() async {
    return openDatabase(
      inMemoryDatabasePath,
      version: 58,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  test('v59 creates all general platform tables', () async {
    final db = await openV58Database();
    try {
      await MigrationV59.migrate(db);

      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
        "('business_profile','business_capabilities','business_template_states',"
        "'feature_flags','tax_profiles','document_tax_snapshots',"
        "'document_reversals','migration_runs')",
      );

      expect(rows.map((row) => row['name']).toSet(), {
        'business_profile',
        'business_capabilities',
        'business_template_states',
        'feature_flags',
        'tax_profiles',
        'document_tax_snapshots',
        'document_reversals',
        'migration_runs',
      });
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('fresh v59 schema includes general platform tables', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
    );
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'business_profile'",
      );
      expect(rows, hasLength(1));
    } finally {
      await db.close();
    }
  });

  test('v59 migration is idempotent and keeps profile empty', () async {
    final db = await openV58Database();
    try {
      await MigrationV59.migrate(db);
      await MigrationV59.migrate(db);

      expect(await db.query('business_profile'), isEmpty);
      expect(
        (await db.rawQuery(
          "SELECT COUNT(*) AS count FROM sqlite_master "
          "WHERE type = 'table' AND name = 'business_profile'",
        )).single['count'],
        1,
      );
    } finally {
      await db.close();
    }
  });

  test('v59 enforces singleton and financial integrity constraints', () async {
    final db = await openV58Database();
    try {
      await MigrationV59.migrate(db);

      await db.insert('business_profile', {
        'id': 1,
        'country_code': 'YE',
        'base_currency_code': 'YER',
        'locale': 'ar',
        'timezone': 'Asia/Aden',
        'tax_mode': 'none',
        'setup_status': 'not_started',
        'setup_version': 1,
        'source': 'migration',
        'created_at': '2026-08-26T00:00:00.000Z',
        'updated_at': '2026-08-26T00:00:00.000Z',
      });

      expect(
        () => db.insert('business_profile', {
          'id': 2,
          'country_code': 'YE',
          'base_currency_code': 'YER',
          'locale': 'ar',
          'timezone': 'Asia/Aden',
          'tax_mode': 'none',
          'setup_status': 'not_started',
          'setup_version': 1,
          'source': 'migration',
          'created_at': '2026-08-26T00:00:00.000Z',
          'updated_at': '2026-08-26T00:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        () => db.insert('tax_profiles', {
          'country_code': 'YE',
          'regime_code': 'invalid',
          'name_ar': 'invalid',
          'rate_bps': -1,
          'calculation_method': 'exclusive',
          'transport_taxable': 0,
          'valid_from': '2026-08-26',
          'requires_confirmation': 1,
          'is_active': 0,
          'created_at': '2026-08-26T00:00:00.000Z',
          'updated_at': '2026-08-26T00:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });
}
