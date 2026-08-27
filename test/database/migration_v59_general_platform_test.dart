import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/migrations/migration_runner.dart';
import 'package:firstpro/data/datasources/migrations/migration_v59.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<String> createV58Fixture() async {
    final path = '${Directory.systemTemp.path}/firstpro_v58_'
        '${DateTime.now().microsecondsSinceEpoch}.db';
    await databaseFactory.deleteDatabase(path);
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 58,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE settings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              key TEXT NOT NULL UNIQUE,
              value TEXT,
              updated_at TEXT
            )
          ''');
          await database.execute('''
            CREATE TABLE currencies (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              code TEXT NOT NULL UNIQUE,
              name_ar TEXT NOT NULL,
              name_en TEXT NOT NULL,
              symbol TEXT NOT NULL,
              is_default INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await database.insert('currencies', {
            'code': 'YER',
            'name_ar': 'الريال اليمني',
            'name_en': 'Yemeni Rial',
            'symbol': 'ر.ي',
            'is_default': 1,
            'is_active': 1,
          });
        },
      ),
    );
    await db.close();
    return path;
  }

  Future<Database> openV58Database() async {
    final path = await createV58Fixture();
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 58),
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

  test('v59 migration is idempotent and backfills profile once', () async {
    final db = await openV58Database();
    try {
      await MigrationV59.migrate(db);
      await MigrationV59.migrate(db);

      final profiles = await db.query('business_profile');
      expect(profiles, hasLength(1));
      expect(profiles.single['source'], 'migration');
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

  test('v58 to v59 upgrade backfills legacy profile and core capabilities',
      () async {
    final path = await createV58Fixture();
    final v58 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 58),
    );
    await v58.insert('settings', {
      'key': 'business_name',
      'value': 'مخبز الاختبار',
      'updated_at': '2026-08-26T00:00:00.000Z',
    });
    await v58.insert('settings', {
      'key': 'default_currency',
      'value': 'YER',
      'updated_at': '2026-08-26T00:00:00.000Z',
    });
    await v58.close();

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 59,
        onUpgrade: MigrationRunner.onUpgrade,
      ),
    );
    try {
      final profile = (await db.query('business_profile')).single;
      expect(profile['business_name'], 'مخبز الاختبار');
      expect(profile['country_code'], 'YE');
      expect(profile['base_currency_code'], 'YER');
      expect(profile['setup_status'], 'not_started');
      expect(profile['source'], 'migration');

      final coreCapabilities = await db.query(
        'business_capabilities',
        columns: ['capability_code'],
        where: 'enabled = 1',
      );
      expect(
        coreCapabilities.map((row) => row['capability_code']).toSet(),
        containsAll({'backup', 'settings', 'audit'}),
      );
    } finally {
      await db.close();
      await databaseFactory.deleteDatabase(path);
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
