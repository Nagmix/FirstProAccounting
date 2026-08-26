import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/platform/onboarding_viewmodel.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/business_profile_repository.dart';
import 'package:firstpro/data/datasources/repositories/capability_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(Database, OnboardingViewModel)> createViewModel() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
    );
    DatabaseHelper.useTestDatabase(db);
    return (
      db,
      OnboardingViewModel(
        profileRepository: BusinessProfileRepository(DatabaseHelper()),
        capabilityRepository: CapabilityRepository(DatabaseHelper()),
      ),
    );
  }

  tearDown(() {
    DatabaseHelper.clearTestDatabase();
  });

  test('fresh owner onboarding loads and saves profile with multiple capabilities', () async {
    final (db, viewModel) = await createViewModel();
    try {
      await viewModel.load();

      expect(viewModel.needsOnboarding, isTrue);
      expect(viewModel.countryCode, 'YE');
      expect(viewModel.baseCurrencyCode, 'YER');
      expect(viewModel.canSave, isFalse);

      viewModel.setBusinessName('متجر البداية');
      viewModel.toggleCapability('sell', true);
      viewModel.toggleCapability('service', true);
      expect(viewModel.selectedCapabilities,
          containsAll({'sell', 'service'}));
      expect(viewModel.canSave, isTrue);

      await viewModel.save();

      expect(viewModel.needsOnboarding, isFalse);
      expect((await db.query('business_profile')), hasLength(1));
      expect(
        await CapabilityRepository(DatabaseHelper()).getEnabledCodes(),
        containsAll({'sell', 'service', 'settle'}),
      );
    } finally {
      await db.close();
    }
  });

  test('legacy database is not blocked by onboarding after upgrade', () async {
    final (db, viewModel) = await createViewModel();
    try {
      await db.insert('settings', {
        'key': 'business_name',
        'value': 'بيانات قديمة',
        'updated_at': '2026-08-26T00:00:00.000Z',
      });

      await viewModel.load();

      expect(viewModel.needsOnboarding, isFalse);
      expect(viewModel.businessName, 'بيانات قديمة');
    } finally {
      await db.close();
    }
  });
}
