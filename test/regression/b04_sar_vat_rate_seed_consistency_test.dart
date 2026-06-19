import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/migrations/seeds.dart';

/// B-04 regression guard: vat_rate for SAR must be 15.0 (15%) in both
/// fresh installs (seedCurrencies) and existing databases (migration_v52).
///
/// Before this fix, seedCurrencies set SAR vat_rate = 0.0, while
/// migration_v52 set it to 15.0 on existing DBs. Fresh installs silently
/// skipped VAT on Saudi invoices — a tax-compliance bug.
///
/// This test verifies that a fresh install via DatabaseSchema.onCreate
/// seeds SAR with vat_rate = 15.0, matching the migration behavior.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('B-04: fresh install seeds SAR with vat_rate = 15.0 (matching migration_v52)', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 53,
      onCreate: (database, version) async {
        await DatabaseSchema.onCreate(database, version);
      },
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );

    final currencies = await db.query('currencies');
    expect(currencies.length, greaterThanOrEqualTo(3),
        reason: 'Should seed at least YER, SAR, USD.');

    final sar = currencies.firstWhere((c) => c['code'] == 'SAR');
    expect(sar['vat_rate'], 15.0,
        reason: 'B-04: SAR vat_rate must be 15.0 (15%) on fresh install, '
            'matching migration_v52.dart. Got: ${sar['vat_rate']}.');

    final yer = currencies.firstWhere((c) => c['code'] == 'YER');
    expect(yer['vat_rate'], 0.0,
        reason: 'YER has no VAT; vat_rate must be 0.0.');

    final usd = currencies.firstWhere((c) => c['code'] == 'USD');
    expect(usd['vat_rate'], 0.0,
        reason: 'USD has no federal VAT; vat_rate must be 0.0 by default.');

    await db.close();
  });

  test('B-04: DatabaseSeeds.seedCurrencies() inserts SAR vat_rate = 15.0', () async {
    // Direct unit test of the seed method, in case a future schema change
    // bypasses DatabaseSchema.onCreate and calls seedCurrencies directly.
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (database, version) async {
        // Minimal currencies table schema (matches schema.dart definition).
        await database.execute('''
          CREATE TABLE currencies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            name_ar TEXT NOT NULL,
            name_en TEXT NOT NULL,
            symbol TEXT NOT NULL,
            exchange_rate REAL NOT NULL DEFAULT 1.0,
            is_default INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            code_offset INTEGER DEFAULT 0,
            vat_rate REAL NOT NULL DEFAULT 0.0,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );

    await DatabaseSeeds.seedCurrencies(db);

    final sar = await db.query('currencies', where: "code = 'SAR'");
    expect(sar, isNotEmpty, reason: 'SAR must be seeded.');
    expect(sar.first['vat_rate'], 15.0,
        reason: 'B-04: DatabaseSeeds.seedCurrencies must set SAR vat_rate '
            'to 15.0, matching migration_v52.');

    await db.close();
  });
}
