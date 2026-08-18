import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/finance/money_engine.dart';
import 'package:firstpro/core/finance/money_value.dart';

void main() {
  group('MoneyEngine', () {
    test('multiplies a unit price by a scaled quantity without floating-point drift', () {
      const unitPrice = MoneyValue(1250, 'YER');

      final result = MoneyEngine().multiply(
        unitPrice: unitPrice,
        quantityScaled: 3,
        scale: 1,
      );

      expect(result.minorUnits, 3750);
      expect(result.currencyCode, 'YER');
    });

    test('rounds half away from zero to a configured minor-unit increment', () {
      const positive = MoneyValue(1005, 'YER');
      const negative = MoneyValue(-1005, 'YER');

      expect(
        MoneyEngine()
            .roundToIncrement(positive, 10, RoundingMode.halfAwayFromZero)
            .minorUnits,
        1010,
      );
      expect(
        MoneyEngine()
            .roundToIncrement(negative, 10, RoundingMode.halfAwayFromZero)
            .minorUnits,
        -1010,
      );
    });
  });
}
