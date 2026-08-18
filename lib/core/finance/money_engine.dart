import 'money_value.dart';

/// Rounding policies used at financial calculation boundaries.
enum RoundingMode {
  /// Ties are rounded away from zero.
  halfAwayFromZero,
}

/// Integer-only monetary calculations.
class MoneyEngine {
  const MoneyEngine();

  /// Multiplies a money value by a rational quantity.
  ///
  /// [quantityScaled] is the quantity multiplied by [scale]. For example,
  /// 1.25 units is represented as `quantityScaled: 125, scale: 100`.
  /// The result is rounded to a whole minor unit using half-away-from-zero.
  MoneyValue multiply({
    required MoneyValue unitPrice,
    required int quantityScaled,
    required int scale,
  }) {
    if (scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be greater than zero');
    }

    final numerator = unitPrice.minorUnits * quantityScaled;
    return MoneyValue(
      _roundDivision(numerator, scale, RoundingMode.halfAwayFromZero),
      unitPrice.currencyCode,
    );
  }

  /// Rounds [value] to the nearest multiple of [incrementMinorUnits].
  MoneyValue roundToIncrement(
    MoneyValue value,
    int incrementMinorUnits,
    RoundingMode mode,
  ) {
    if (incrementMinorUnits <= 0) {
      throw ArgumentError.value(
        incrementMinorUnits,
        'incrementMinorUnits',
        'must be greater than zero',
      );
    }

    final roundedQuotient = _roundDivision(
      value.minorUnits,
      incrementMinorUnits,
      mode,
    );
    return MoneyValue(
      roundedQuotient * incrementMinorUnits,
      value.currencyCode,
    );
  }

  int _roundDivision(int numerator, int denominator, RoundingMode mode) {
    if (denominator <= 0) {
      throw ArgumentError.value(denominator, 'denominator');
    }

    final quotient = numerator ~/ denominator;
    final remainder = numerator.remainder(denominator).abs();
    if (remainder == 0) return quotient;

    switch (mode) {
      case RoundingMode.halfAwayFromZero:
        if (remainder * 2 >= denominator) {
          return quotient + (numerator.isNegative ? -1 : 1);
        }
        return quotient;
    }
  }
}
