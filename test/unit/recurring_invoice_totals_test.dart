import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/data/datasources/database_helper.dart';
import 'package:firstpro/data/datasources/repositories/invoice_repository.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/recurring_invoice_service.dart';

void main() {
  test('recurring template totals use minor units and the shared tax engine', () {
    final service = RecurringInvoiceService(
      DatabaseHelper(),
      InvoiceRepository(DatabaseHelper()),
      ReferenceDataRepository(DatabaseHelper()),
    );

    final totals = service.calculateTemplateTotals(
      subtotalMinorUnits: 1001,
      discountMinorUnits: 1,
      transportMinorUnits: 25,
      taxRateBasisPoints: 500,
      taxInclusive: false,
    );

    expect(totals.taxableMinorUnits, 1000);
    expect(totals.taxMinorUnits, 50);
    expect(totals.totalMinorUnits, 1075);
  });

  test('recurring template totals can include taxable transport', () {
    final service = RecurringInvoiceService(
      DatabaseHelper(),
      InvoiceRepository(DatabaseHelper()),
      ReferenceDataRepository(DatabaseHelper()),
    );

    final totals = service.calculateTemplateTotals(
      subtotalMinorUnits: 1000,
      discountMinorUnits: 0,
      transportMinorUnits: 100,
      taxRateBasisPoints: 1000,
      taxInclusive: false,
      transportTaxable: true,
    );

    expect(totals.taxMinorUnits, 110);
    expect(totals.totalMinorUnits, 1210);
  });
}
