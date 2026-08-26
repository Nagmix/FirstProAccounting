import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/tax_policy_resolver.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/tax_policy_repository.dart';
import 'package:firstpro/data/models/tax_profile_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('500 basis points are calculated as 5 percent without using currency tax',
      () async {
    final (db, resolver, repository) = await _createResolver();
    try {
      await repository.save(_profile(rateBasisPoints: 500));

      final profile = await resolver.resolveFor(
        date: DateTime.utc(2026, 8, 26),
        countryCode: 'XX',
      );
      final totals = resolver.calculateTotals(
        profile: profile,
        subtotalMinorUnits: 1000,
        discountMinorUnits: 0,
        transportMinorUnits: 0,
        taxInclusive: false,
      );

      expect(profile?.rateBasisPoints, 500);
      expect(totals.taxMinorUnits, 50);
      expect(totals.totalMinorUnits, 1050);
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });

  test('taxable transport is included in the tax base only when policy allows it',
      () async {
    final (db, resolver, repository) = await _createResolver();
    try {
      await repository.save(_profile(rateBasisPoints: 1000, transportTaxable: true));
      final profile = await resolver.resolveFor(
        date: DateTime.utc(2026, 8, 26),
        countryCode: 'XX',
      );
      final totals = resolver.calculateTotals(
        profile: profile,
        subtotalMinorUnits: 1000,
        discountMinorUnits: 0,
        transportMinorUnits: 100,
        taxInclusive: false,
      );

      expect(totals.taxMinorUnits, 110);
      expect(totals.totalMinorUnits, 1210);
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });

  test('exclusive policy overrides a contradictory inclusive caller flag', () async {
    final (db, resolver, repository) = await _createResolver();
    try {
      await repository.save(_profile(rateBasisPoints: 1000));
      final profile = await resolver.resolveFor(
        date: DateTime.utc(2026, 8, 26),
        countryCode: 'XX',
      );
      final totals = resolver.calculateTotals(
        profile: profile,
        subtotalMinorUnits: 1000,
        discountMinorUnits: 0,
        transportMinorUnits: 0,
        taxInclusive: true,
      );

      expect(totals.taxMinorUnits, 100);
      expect(totals.totalMinorUnits, 1100);
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });

  test('dated policies resolve and no-policy mode produces zero tax', () async {
    final (db, resolver, repository) = await _createResolver();
    try {
      await repository.save(_profile(
        rateBasisPoints: 700,
        validFrom: DateTime.utc(2027, 1, 1),
      ));

      final before = await resolver.resolveFor(
        date: DateTime.utc(2026, 12, 31),
        countryCode: 'XX',
      );
      final after = await resolver.resolveFor(
        date: DateTime.utc(2027, 1, 1),
        countryCode: 'XX',
      );

      expect(before, isNull);
      expect(after?.rateBasisPoints, 700);
      expect(
        resolver.calculateTotals(
          profile: before,
          subtotalMinorUnits: 1000,
          discountMinorUnits: 0,
          transportMinorUnits: 0,
          taxInclusive: false,
        ).taxMinorUnits,
        0,
      );
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });
}

Future<(Database, TaxPolicyResolver, TaxPolicyRepository)> _createResolver() async {
  final db = await openDatabase(
    inMemoryDatabasePath,
    version: 59,
    onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
  );
  DatabaseHelper.useTestDatabase(db);
  final repository = TaxPolicyRepository(DatabaseHelper());
  return (db, TaxPolicyResolver(repository), repository);
}

TaxProfile _profile({
  required int rateBasisPoints,
  DateTime? validFrom,
  bool transportTaxable = false,
  String calculationMethod = 'exclusive',
}) {
  final from = validFrom ?? DateTime.utc(2026, 1, 1);
  return TaxProfile(
    countryCode: 'XX',
    regimeCode: 'standard',
    nameAr: 'سياسة اختبارية',
    rateBasisPoints: rateBasisPoints,
    calculationMethod: calculationMethod,
    transportTaxable: transportTaxable,
    validFrom: from,
    requiresConfirmation: false,
    sourceNote: 'test',
    isActive: true,
  );
}
