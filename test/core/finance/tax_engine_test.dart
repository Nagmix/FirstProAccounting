import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/tax_engine.dart';

void main() {
  group('TaxEngine', () {
    test('calculates exclusive tax using integer minor units', () {
      final result = const TaxEngine().calculate(
        taxableMinorUnits: 10000,
        rateBasisPoints: 1500,
        isInclusive: false,
      );

      expect(result.netMinorUnits, 10000);
      expect(result.taxMinorUnits, 1500);
      expect(result.grossMinorUnits, 11500);
    });

    test('extracts inclusive tax without adding tax twice', () {
      final result = const TaxEngine().calculate(
        taxableMinorUnits: 11500,
        rateBasisPoints: 1500,
        isInclusive: true,
      );

      expect(result.netMinorUnits, 10000);
      expect(result.taxMinorUnits, 1500);
      expect(result.grossMinorUnits, 11500);
    });

    test('preserves the sign for credit notes and returns', () {
      final result = const TaxEngine().calculate(
        taxableMinorUnits: -10000,
        rateBasisPoints: 1500,
        isInclusive: false,
      );

      expect(result.netMinorUnits, -10000);
      expect(result.taxMinorUnits, -1500);
      expect(result.grossMinorUnits, -11500);
    });
  });
}
