/// Fixed-point currency conversion at the database boundary.
///
/// Exchange rates use six decimal places: 140.000000 is 140000000.
class CurrencyEngine {
  const CurrencyEngine();

  static const int rateScale = 1000000;

  static int rateToMicros(double rate) => (rate * rateScale).round();

  int convertMajorUnits({
    required double amount,
    required double exchangeRate,
  }) {
    return convertMinorUnits(
      amountMinorUnits: _toMinorUnits(amount),
      exchangeRateMicros: rateToMicros(exchangeRate),
    );
  }

  int _toMinorUnits(double amount) => (amount * 100).round();

  int convertMinorUnits({
    required int amountMinorUnits,
    required int exchangeRateMicros,
  }) {
    if (exchangeRateMicros < 0) {
      throw ArgumentError.value(
        exchangeRateMicros,
        'exchangeRateMicros',
        'cannot be negative',
      );
    }

    final numerator = amountMinorUnits * exchangeRateMicros;
    final quotient = numerator ~/ rateScale;
    final remainder = numerator.remainder(rateScale).abs();
    if (remainder * 2 >= rateScale) {
      return quotient + (numerator.isNegative ? -1 : 1);
    }
    return quotient;
  }
}
