import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/business_profile_repository.dart';
import 'package:firstpro/data/models/business_profile_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(Database, BusinessProfileRepository)> createRepository() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    return (db, BusinessProfileRepository(DatabaseHelper()));
  }

  tearDown(() {
    DatabaseHelper.clearTestDatabase();
  });

  test('fresh v59 database contains safe Yemen migration defaults', () async {
    final (db, repository) = await createRepository();
    try {
      final profile = await repository.getOrCreateProfile();

      expect(profile.countryCode, 'YE');
      expect(profile.baseCurrencyCode, 'YER');
      expect(profile.locale, 'ar');
      expect(profile.timezone, 'Asia/Aden');
      expect(profile.taxMode, 'none');
      expect(profile.setupStatus, 'not_started');
      final rows = await db.query('business_profile');
      expect(rows, hasLength(1));
      expect(rows.single['source'], 'migration');
    } finally {
      await db.close();
    }
  });

  test('legacy settings hydrate typed profile when the typed row is absent', () async {
    final (db, repository) = await createRepository();
    try {
      await db.delete('business_profile');
      await db.insert('settings', {
        'key': 'business_name',
        'value': 'متجر الاختبار',
        'updated_at': '2026-08-26T00:00:00.000Z',
      });
      await db.insert('settings', {
        'key': 'business_phone',
        'value': '777000000',
        'updated_at': '2026-08-26T00:00:00.000Z',
      });
      await db.insert('settings', {
        'key': 'default_currency',
        'value': 'USD',
        'updated_at': '2026-08-26T00:00:00.000Z',
      });

      final profile = await repository.getOrCreateProfile();

      expect(profile.businessName, 'متجر الاختبار');
      expect(profile.phone, '777000000');
      expect(profile.baseCurrencyCode, 'USD');
      expect(profile.source, 'legacy_settings');
      expect(await db.query('business_profile'), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('saving typed profile synchronizes the default currency marker', () async {
    final (db, repository) = await createRepository();
    try {
      final profile = BusinessProfile(
        businessName: 'متجر متعدد العملات',
        phone: null,
        email: null,
        address: null,
        logoPath: null,
        countryCode: 'YE',
        baseCurrencyCode: 'USD',
        locale: 'ar',
        timezone: 'Asia/Aden',
        taxMode: 'none',
        setupStatus: 'completed',
        setupVersion: 1,
        source: 'onboarding',
      );

      await repository.saveProfile(profile);

      final currencies = await db.query(
        'currencies',
        columns: ['code', 'is_default'],
        where: 'code IN (?, ?)',
        whereArgs: ['YER', 'USD'],
      );
      expect(currencies.firstWhere((row) => row['code'] == 'USD')['is_default'], 1);
      expect(currencies.firstWhere((row) => row['code'] == 'YER')['is_default'], 0);
    } finally {
      await db.close();
    }
  });

  test('saving typed profile rejects an inactive base currency atomically', () async {
    final (db, repository) = await createRepository();
    try {
      await db.update(
        'currencies',
        {'is_active': 0},
        where: 'code = ?',
        whereArgs: ['USD'],
      );
      final profile = BusinessProfile(
        businessName: 'متجر عملة غير فعالة',
        phone: null,
        email: null,
        address: null,
        logoPath: null,
        countryCode: 'YE',
        baseCurrencyCode: 'USD',
        locale: 'ar',
        timezone: 'Asia/Aden',
        taxMode: 'none',
        setupStatus: 'completed',
        setupVersion: 1,
        source: 'onboarding',
      );

      await expectLater(
        repository.saveProfile(profile),
        throwsA(isA<ArgumentError>()),
      );
      final currencies = await db.query(
        'currencies',
        columns: ['code', 'is_default', 'is_active'],
        where: 'code IN (?, ?)',
        whereArgs: ['YER', 'USD'],
      );
      expect(currencies.firstWhere((row) => row['code'] == 'YER')['is_default'], 1);
      expect(currencies.firstWhere((row) => row['code'] == 'USD')['is_default'], 0);
    } finally {
      await db.close();
    }
  });

  test('saving typed profile is idempotent and locks base currency after posted data', async () {
    final (db, repository) = await createRepository();
    try {
      final profile = BusinessProfile(
        businessName: 'متجر جديد',
        phone: '777111111',
        email: null,
        address: null,
        logoPath: null,
        countryCode: 'YE',
        baseCurrencyCode: 'YER',
        locale: 'ar',
        timezone: 'Asia/Aden',
        taxMode: 'none',
        setupStatus: 'completed',
        setupVersion: 1,
        source: 'onboarding',
      );

      await repository.saveProfile(profile);
      await repository.saveProfile(profile);
      expect(await db.query('business_profile'), hasLength(1));

      await db.insert('invoices', {
        'id': 'POSTED-1',
        'type': 'sale',
        'is_posted': 1,
        'created_at': '2026-08-26T00:00:00.000Z',
      });

      expect(await repository.hasPostedFinancialData(), isTrue);
      expect(await repository.canChangeBaseCurrency('USD'), isFalse);
      expect(await repository.canChangeBaseCurrency('YER'), isTrue);
    } finally {
      await db.close();
    }
  });
}
