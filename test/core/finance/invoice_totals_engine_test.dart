import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/invoice_totals_engine.dart';

void main() {
  test('calculates discount, exclusive tax, transport, and total in cents', () {
    final result = const InvoiceTotalsEngine().calculate(
      subtotalMinorUnits: 100000,
      discountMinorUnits: 10000,
      transportMinorUnits: 5000,
      taxRateBasisPoints: 1500,
      taxInclusive: false,
    );

    expect(result.taxableMinorUnits, 90000);
    expect(result.taxMinorUnits, 13500);
    expect(result.totalMinorUnits, 108500);
  });

  test('rejects a discount greater than a positive subtotal', () {
    expect(
      () => const InvoiceTotalsEngine().calculate(
        subtotalMinorUnits: 10000,
        discountMinorUnits: 10001,
        transportMinorUnits: 0,
        taxRateBasisPoints: 1500,
        taxInclusive: false,
      ),
      throwsArgumentError,
    );
  });
}
