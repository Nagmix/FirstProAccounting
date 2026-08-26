import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/capability_catalog.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('catalog resolves capability dependencies without business types', () {
    final resolved = CapabilityCatalog.resolveDependencies({'transform'});

    expect(resolved, containsAll({'transform', 'stock'}));
    expect(CapabilityCatalog.byCode('service').dependencies, isNotEmpty);
    expect(
      () => CapabilityCatalog.byCode('bakery'),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => CapabilityCatalog.validateNoCycles(), returnsNormally);
  });

  test('catalog keeps core capabilities outside optional selection', () {
    final core = CapabilityCatalog.definitions.where((definition) => definition.isCore);

    expect(core.map((definition) => definition.code), contains('backup'));
    expect(core.map((definition) => definition.code), contains('audit'));
  });

  Future<(Database, CapabilityRepository)> createRepository() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    return (db, CapabilityRepository(DatabaseHelper()));
  }

  tearDown(() {
    DatabaseHelper.clearTestDatabase();
  });

  test('repository persists resolved multi-select capabilities idempotently', () async {
    final (db, repository) = await createRepository();
    try {
      await repository.replaceEnabledCodes({'transform'}, source: 'onboarding');
      await repository.replaceEnabledCodes({'transform'}, source: 'onboarding');

      final enabled = await repository.getEnabledCodes();
      expect(enabled, containsAll({'transform', 'stock'}));
      expect(
        (await db.rawQuery('SELECT COUNT(*) AS count FROM business_capabilities'))
            .single['count'],
        2,
      );
    } finally {
      await db.close();
    }
  });

  test('repository refuses disabling core capabilities', () async {
    final (db, repository) = await createRepository();
    try {
      await expectLater(
        repository.setEnabled('backup', false, source: 'settings'),
        throwsA(isA<StateError>()),
      );
    } finally {
      await db.close();
    }
  });

  test('repository refuses disabling a capability required by an enabled dependent', () async {
    final (db, repository) = await createRepository();
    try {
      await repository.setEnabled('transform', true, source: 'settings');
      await expectLater(
        repository.setEnabled('stock', false, source: 'settings'),
        throwsA(isA<StateError>()),
      );
      expect(await repository.getEnabledCodes(), containsAll({'transform', 'stock'}));
    } finally {
      await db.close();
    }
  });

  test('schedule data check reads the persisted promised_at field', () async {
    final (db, repository) = await createRepository();
    try {
      await db.insert('service_orders', {
        'id': 'SCHEDULE-1',
        'order_number': 'SO-1',
        'status': 'draft',
        'received_at': '2026-08-26T08:00:00.000Z',
        'promised_at': '2026-08-27T08:00:00.000Z',
        'created_at': '2026-08-26T08:00:00.000Z',
        'updated_at': '2026-08-26T08:00:00.000Z',
      });

      expect(await repository.hasDataFor('schedule'), isTrue);
    } finally {
      await db.close();
    }
  });

  test('disabling a used capability hides it without deleting financial data', () async {
    final (db, repository) = await createRepository();
    try {
      await db.insert('invoices', {
        'id': 'CAP-SELL-1',
        'type': 'sale',
        'is_posted': 1,
        'created_at': '2026-08-26T00:00:00.000Z',
      });
      await repository.setEnabled('sell', false, source: 'user');

      expect(await repository.hasDataFor('sell'), isTrue);
      expect(await repository.getEnabledCodes(), isNot(contains('sell')));
      expect(await db.query('invoices', where: 'id = ?', whereArgs: ['CAP-SELL-1']),
          hasLength(1));
    } finally {
      await db.close();
    }
  });
}
