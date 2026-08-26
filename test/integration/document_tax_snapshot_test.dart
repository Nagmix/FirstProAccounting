import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/invoice_totals_engine.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/migrations/schema.dart';
import 'package:firstpro/data/datasources/repositories/tax_policy_repository.dart';
import 'package:firstpro/data/models/document_tax_snapshot_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('document tax snapshot remains unchanged after current policy changes',
      () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 59,
      onCreate: (database, version) => DatabaseSchema.onCreate(database, version),
    );
    DatabaseHelper.useTestDatabase(db);
    final repository = TaxPolicyRepository(DatabaseHelper());
    try {
      final totals = const InvoiceTotalsEngine().calculate(
        subtotalMinorUnits: 1000,
        discountMinorUnits: 0,
        transportMinorUnits: 0,
        taxRateBasisPoints: 500,
        taxInclusive: false,
      );
      final original = DocumentTaxSnapshot(
        documentType: 'invoice',
        documentId: 'INV-TAX-1',
        countryCode: 'XX',
        regimeCode: 'standard',
        rateBasisPoints: 500,
        calculationMethod: 'exclusive',
        transportTaxable: false,
        taxableSubtotalMinor: totals.taxableMinorUnits,
        taxableTransportMinor: 0,
        discountMinor: totals.discountMinorUnits,
        taxMinor: totals.taxMinorUnits,
        roundingMode: 'half_up',
        source: 'test',
      );

      await repository.saveSnapshot(original);
      final changed = original.copyWith(rateBasisPoints: 1500, taxMinor: 150);
      await expectLater(repository.saveSnapshot(changed), throwsA(isA<StateError>()));

      final stored = await repository.getSnapshot('invoice', 'INV-TAX-1');
      expect(stored?.rateBasisPoints, 500);
      expect(stored?.taxMinor, 50);
    } finally {
      await db.close();
      DatabaseHelper.clearTestDatabase();
    }
  });
}
